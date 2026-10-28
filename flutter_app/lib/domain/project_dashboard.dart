import 'documentation_model.dart';
import 'materials_calculator.dart';
import 'models.dart';
import 'room_documentation_status.dart';

class RoomAttentionItem {
  const RoomAttentionItem({
    required this.room,
    required this.summary,
    required this.missingCount,
  });

  final Room room;
  final RoomDocumentationSummary summary;
  final int missingCount;

  bool get isReady => summary.readyForHandover;
  bool get hasLayout => room.hasLayout;
}

class ProjectDashboardSummary {
  const ProjectDashboardSummary({
    required this.project,
    required this.roomCount,
    required this.readyCount,
    required this.totalAreaM2,
    required this.totalPerimeterM,
    required this.designDoneTotal,
    required this.designStepsTotal,
    required this.hiddenDoneTotal,
    required this.hiddenStepsTotal,
    required this.rooms,
    required this.needsAttention,
    required this.urgentCount,
  });

  final Project project;
  final int roomCount;
  final int readyCount;
  final double totalAreaM2;
  final double totalPerimeterM;
  final int designDoneTotal;
  final int designStepsTotal;
  final int hiddenDoneTotal;
  final int hiddenStepsTotal;
  final List<RoomAttentionItem> rooms;
  final List<RoomAttentionItem> needsAttention;
  final int urgentCount;

  double get readyRatio => roomCount == 0 ? 0 : readyCount / roomCount;

  String get readyLabel => roomCount == 0 ? '—' : '$readyCount / $roomCount';
}

ProjectDashboardSummary buildProjectDashboard(Project project) {
  var area = 0.0;
  var perimeter = 0.0;
  var ready = 0;
  var designDone = 0;
  var designTotal = 0;
  var hiddenDone = 0;
  var hiddenTotal = 0;
  var urgent = 0;
  final items = <RoomAttentionItem>[];

  for (final room in project.rooms) {
    if (room.hasLayout) {
      area += MaterialsCalculator.roomAreaM2(room.walls);
      perimeter += MaterialsCalculator.roomPerimeterCm(room.walls) / 100;
    }
    final checklist = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
    if (checklist.priority == RoomFieldPriority.urgent) urgent++;
    final summary = roomDocumentationSummary(room, project, checklist: checklist);
    if (summary.readyForHandover) ready++;
    designDone += summary.designDone;
    designTotal += summary.designTotal;
    hiddenDone += summary.hiddenWorksDone;
    hiddenTotal += summary.hiddenWorksTotal;
    items.add(RoomAttentionItem(
      room: room,
      summary: summary,
      missingCount: summary.missingItems.length,
    ));
  }

  items.sort((a, b) {
    if (a.isReady != b.isReady) return a.isReady ? 1 : -1;
    if (a.missingCount != b.missingCount) return b.missingCount.compareTo(a.missingCount);
    return a.room.name.compareTo(b.room.name);
  });

  final needsAttention = items
      .where((i) => !i.isReady && (i.missingCount > 0 || !i.hasLayout))
      .toList();

  return ProjectDashboardSummary(
    project: project,
    roomCount: project.rooms.length,
    readyCount: ready,
    totalAreaM2: area,
    totalPerimeterM: perimeter,
    designDoneTotal: designDone,
    designStepsTotal: designTotal,
    hiddenDoneTotal: hiddenDone,
    hiddenStepsTotal: hiddenTotal,
    rooms: items,
    needsAttention: needsAttention,
    urgentCount: urgent,
  );
}

