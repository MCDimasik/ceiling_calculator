import 'special_space.dart';
import 'models.dart';

/// Floors UX across modules
/// ---------------------
/// - Rooms list: swipe FAB Комната↔Этаж; pager chips only when 2+ floors.
/// - Finish / documentation room lists: same pager; room subtitle may show
///   [roomFloorLabel] when floors are explicit.
/// - Materials (ceiling & finish): floor chip filters which rooms enter the BOM.
/// - Typical group (e.g. «2–6 типовой»): one pager page; copies stay in DB for
///   qty×N later, but UI edits the template floor (typicalIndex == 0).
/// - Docs/KS/KP: still project- or room-scoped; floor filter can narrow room
///   sets before [buildWorkLines] when exporting from a floor page.
/// - Stairwells with floorsFrom–floorsTo appear on each overlapping floor page
///   in the rooms list ([includeSpanningStairwells]); BOM still counts once.

/// Floors visible in the pager (templates only). Empty ⇒ single implicit floor.
List<ProjectFloor> floorsForPager(Iterable<ProjectFloor> floors) {
  final list = floors.where((f) => f.showInPager).toList()
    ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
  return list;
}

/// Whether UI should mention floors at all.
bool projectHasExplicitFloors(Iterable<ProjectFloor> floors) =>
    floorsForPager(floors).length > 1 ||
    floors.any((f) => f.floorNumber > 1 || f.isTypicalGroup);

List<Room> roomsOnFloor(Iterable<Room> rooms, ProjectFloor? floor) {
  if (floor?.id == null) {
    return rooms.where((r) => r.floorId == null).toList();
  }
  final id = floor!.id!;
  return rooms.where((r) => r.floorId == id).toList();
}

/// Whether a stairwell's этаж с…по overlaps the pager floor number range.
bool stairwellSpansFloorPage(Room room, ProjectFloor page) {
  final space = room.specialSpace;
  if (space == null || space.kind != SpecialSpaceKind.stairwell) return false;
  final st = space.stair;
  if (st == null) return false;
  final a = st.floorsFrom <= st.floorsTo ? st.floorsFrom : st.floorsTo;
  final b = st.floorsFrom <= st.floorsTo ? st.floorsTo : st.floorsFrom;
  final pageLo = page.floorNumber;
  final pageHi = page.typicalSpanEnd ?? page.floorNumber;
  return a <= pageHi && b >= pageLo;
}

/// Stairwells anchored on a floor about to be deleted, but still needed on
/// remaining floors (span эт. с…по overlaps another kept floor).
List<Room> spanningStairwellsAtRiskOnFloorDelete({
  required Iterable<Room> rooms,
  required Iterable<ProjectFloor> floors,
  required Set<int> deletingFloorIds,
}) {
  if (deletingFloorIds.isEmpty) return const [];
  final remaining = floors
      .where((f) => f.id != null && !deletingFloorIds.contains(f.id))
      .toList();
  if (remaining.isEmpty) return const [];
  final out = <Room>[];
  for (final room in rooms) {
    final fid = room.floorId;
    if (fid == null || !deletingFloorIds.contains(fid)) continue;
    if (!remaining.any((f) => stairwellSpansFloorPage(room, f))) continue;
    out.add(room);
  }
  return out;
}

/// Prefer a remaining floor that overlaps the stairwell span; else first kept.
ProjectFloor? preferReassignFloorForStairwell({
  required Room room,
  required Iterable<ProjectFloor> floors,
  required Set<int> deletingFloorIds,
}) {
  final remaining = floors
      .where((f) => f.id != null && !deletingFloorIds.contains(f.id))
      .toList()
    ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
  if (remaining.isEmpty) return null;
  for (final f in remaining) {
    if (stairwellSpansFloorPage(room, f)) return f;
  }
  return remaining.first;
}

/// Rooms for a pager page: template floor, or all rooms when floors are implicit.
///
/// When [includeSpanningStairwells] is true (rooms list UI), a stairwell with
/// «эт. с…по» also appears on every overlapping floor page — same room id,
/// not a copy. Keep false for BOM / materials so areas are not multiplied.
List<Room> roomsForPagerFloor({
  required Iterable<Room> rooms,
  required List<ProjectFloor> floors,
  required ProjectFloor? selected,
  bool includeSpanningStairwells = false,
}) {
  if (!projectHasExplicitFloors(floors)) {
    return List<Room>.from(rooms);
  }
  if (selected == null) {
    return rooms.where((r) => r.floorId == null).toList();
  }
  final base = roomsOnFloor(rooms, selected);
  if (!includeSpanningStairwells) return base;
  final seen = {for (final r in base) r.id};
  final extras = <Room>[];
  for (final r in rooms) {
    if (r.id != null && seen.contains(r.id)) continue;
    if (!stairwellSpansFloorPage(r, selected)) continue;
    extras.add(r);
    if (r.id != null) seen.add(r.id);
  }
  if (extras.isEmpty) return base;
  return [...base, ...extras];
}

String? roomFloorLabel({
  required Room room,
  required List<ProjectFloor> floors,
}) {
  if (!projectHasExplicitFloors(floors)) return null;
  final id = room.floorId;
  if (id == null) {
    final first = floorsForPager(floors).where((f) => f.floorNumber == 1);
    return first.isEmpty ? '1 этаж' : first.first.pagerLabel;
  }
  for (final f in floors) {
    if (f.id == id) return f.pagerLabel;
  }
  return null;
}
