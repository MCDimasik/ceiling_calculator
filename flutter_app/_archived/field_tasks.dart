import 'documentation_model.dart';
import 'ks2_act_service.dart';
import 'models.dart';
import 'room_documentation_status.dart';

class FieldTask {
  const FieldTask({
    required this.projectId,
    required this.projectName,
    required this.roomId,
    required this.roomName,
    required this.message,
    required this.priority,
    this.stepId,
    this.assignee = '',
    this.dueDate,
  });

  final int projectId;
  final String projectName;
  final int roomId;
  final String roomName;
  final String message;
  final RoomFieldPriority priority;
  final String? stepId;
  final String assignee;
  final DateTime? dueDate;

  bool get isUrgent => priority == RoomFieldPriority.urgent;
  bool get isBlocked => priority == RoomFieldPriority.blocked;

  String get metaLine {
    final parts = <String>[];
    if (assignee.isNotEmpty) parts.add(assignee);
    if (dueDate != null) parts.add('до ${_fmtDate(dueDate!)}');
    return parts.join(' · ');
  }
}

/// In-app task list (offline substitute for push notifications).
List<FieldTask> buildFieldTasks(Project project) {
  final tasks = <FieldTask>[];
  final pid = project.id;
  if (pid == null) return tasks;

  for (final room in project.rooms) {
    final rid = room.id;
    if (rid == null) continue;
    final cl = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson);
    final summary = roomDocumentationSummary(room, project, checklist: cl);

    FieldTask make({
      required String message,
      required RoomFieldPriority priority,
      String? stepId,
    }) =>
        FieldTask(
          projectId: pid,
          projectName: project.name,
          roomId: rid,
          roomName: room.name,
          message: message,
          priority: priority,
          stepId: stepId,
          assignee: cl.assignee,
          dueDate: cl.dueDate,
        );

    if (cl.dueDate != null && cl.dueDate!.isBefore(DateTime.now())) {
      tasks.add(make(
        message: 'Просрочен срок: ${_fmtDate(cl.dueDate!)}',
        priority: RoomFieldPriority.urgent,
      ));
    }

    if (cl.priority == RoomFieldPriority.blocked) {
      tasks.add(make(
        message: cl.notes.isNotEmpty ? 'Стоп: ${cl.notes}' : 'Комната на стопе',
        priority: RoomFieldPriority.blocked,
      ));
      continue;
    }

    for (final mt in cl.manualTasks.where((t) => !t.done)) {
      tasks.add(make(
        message: mt.message,
        priority: cl.priority,
        stepId: 'manual:${mt.id}',
      ));
    }

    if (!room.hasLayout) {
      tasks.add(make(
        message: 'Нет чертежа / раскладки',
        priority: cl.priority,
      ));
      continue;
    }

    for (final step in summary.steps.where((s) => s.applies && !s.done)) {
      if (step.step.phase != DocumentationPhase.hiddenWorks) continue;
      final photos = cl.photosFor(step.step.id);
      if (photos.isNotEmpty) continue;
      tasks.add(make(
        message: 'Нет фото: ${step.step.title}',
        priority: cl.priority,
        stepId: step.step.id,
      ));
    }

    if (cl.priority == RoomFieldPriority.urgent && summary.missingItems.isNotEmpty) {
      final already = tasks.any((t) => t.roomId == rid);
      if (!already) {
        tasks.add(make(
          message: 'Срочно: ${summary.missingItems.first}',
          priority: RoomFieldPriority.urgent,
        ));
      }
    }
  }

  tasks.addAll(/* ARCHIVED: buildProjectFactAlertTasks(project) */ const <FieldTask>[]);
  tasks.addAll(_ks2ClosureTasks(project));

  tasks.sort((a, b) {
    int rank(RoomFieldPriority p) => switch (p) {
          RoomFieldPriority.blocked => 0,
          RoomFieldPriority.urgent => 1,
          RoomFieldPriority.normal => 2,
        };
    final c = rank(a.priority).compareTo(rank(b.priority));
    if (c != 0) return c;
    return a.roomName.compareTo(b.roomName);
  });
  return tasks;
}

List<FieldTask> _ks2ClosureTasks(Project project) {
  final pid = project.id;
  if (pid == null) return const [];
  final out = <FieldTask>[];
  for (final e in ks2ClosureAlerts(project)) {
    out.add(FieldTask(
      projectId: pid,
      projectName: project.name,
      roomId: 0,
      roomName: 'Объект',
      message: 'КС-2 ${e.$1.labelRu}: ${e.$2}',
      priority: RoomFieldPriority.normal,
      stepId: 'ks2_close_${e.$1.name}',
    ));
  }
  return out;
}

int countFieldTasks(Project project) => buildFieldTasks(project).length;

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
