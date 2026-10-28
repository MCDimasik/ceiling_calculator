import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/act_export.dart';
import 'package:ceiling_calculator/domain/documentation_model.dart';
import 'package:ceiling_calculator/domain/documentation_step_logic.dart';
import 'package:ceiling_calculator/domain/finish_model.dart';
import 'package:ceiling_calculator/domain/models.dart';
import 'package:ceiling_calculator/domain/room_documentation_status.dart';
import 'package:ceiling_calculator/domain/vedomost_export.dart';

void main() {
  test('finish documentation summary tracks design steps', () {
    final project = Project(name: 'Obj');
    final room = Room(
      name: 'Hall',
      walls: [
        [0, 0, 600, 0],
        [600, 0, 600, 600],
        [600, 600, 0, 600],
        [0, 600, 0, 0],
      ],
      layoutConfirmed: true,
      ceilingGuides: [
        {'axis': 'h', 'line': 0, 'kind': '3600'},
      ],
      lightFixtures: [
        [1, 1],
      ],
      wallFinishLayers: [
        FinishLayer(kind: FinishLayerKind.plaster, enabled: true).toJson(),
      ],
    );
    final summary = roomDocumentationSummary(room, project);
    expect(summary.steps.firstWhere((s) => s.step.id == 'drawing').done, isTrue);
    expect(summary.steps.firstWhere((s) => s.step.id == 'walls_plan').done, isTrue);
    expect(summary.steps.firstWhere((s) => s.step.id == 'ceiling_layout').done, isTrue);
    expect(summary.designDone, greaterThan(4));
    expect(summary.designTotal, greaterThan(0));
    expect(summary.hiddenWorksTotal, greaterThan(0));
  });

  test('hidden work N/A when no wall layers', () {
    final project = Project(name: 'Obj');
    final room = Room(
      name: 'Empty',
      walls: [
        [0, 0, 400, 0],
        [400, 0, 400, 400],
        [400, 400, 0, 400],
        [0, 400, 0, 0],
      ],
    );
    final ctx = RoomDocContext.fromRoom(room);
    expect(ctx.hiddenWorkApplies('hw_walls'), isFalse);
    final summary = roomDocumentationSummary(room, project);
    final hwWalls = summary.steps.firstWhere((s) => s.step.id == 'hw_walls');
    expect(hwWalls.applies, isFalse);
    expect(hwWalls.done, isTrue);
  });

  test('missing items lists incomplete applicable steps', () {
    final project = Project(name: 'Obj');
    final room = Room(name: 'New');
    final summary = roomDocumentationSummary(room, project);
    expect(summary.missingItems, isNotEmpty);
    expect(summary.missingItems, contains('Чертёж помещения'));
  });

  test('vedomost text includes finish scope', () {
    final project = Project(name: 'Office');
    final room = Room(
      name: 'Room 1',
      walls: [
        [0, 0, 600, 0],
        [600, 0, 600, 600],
        [600, 600, 0, 600],
        [0, 600, 0, 0],
      ],
    );
    final stamp = DocumentationStamp(objectName: 'Office', customer: 'LLC Test');
    final text = buildVedomostText(project: project, room: room, stamp: stamp);
    expect(text, contains('КОМПЛЕКС ОТДЕЛКИ'));
    expect(text, contains('Office'));
    expect(text, contains('ОТДЕЛКА'));
  });

  test('hidden work done with photo path', () {
    final cl = RoomDocumentationChecklist(
      stepPhotos: {'hw_floor': ['/tmp/a.jpg']},
    );
    expect(cl.hiddenWorkDone('hw_floor'), isTrue);
  });

  test('hidden work done with confirm without photo', () {
    final cl = RoomDocumentationChecklist(
      hiddenWorksConfirmed: {'hw_floor': true},
    );
    expect(cl.hiddenWorkDone('hw_floor'), isTrue);
  });

  test('hidden works act text includes object and steps', () {
    final project = Project(name: 'Office');
    final room = Room(
      name: 'Cabinet',
      walls: [
        [0, 0, 400, 0],
        [400, 0, 400, 300],
        [400, 300, 0, 300],
        [0, 300, 0, 0],
      ],
    );
    final text = buildHiddenWorksActText(
      project: project,
      room: room,
      stamp: DocumentationStamp(objectName: 'Office'),
      checklist: RoomDocumentationChecklist(),
    );
    expect(text, contains('АКТ ОСМОТРА СКРЫТЫХ РАБОТ'));
    expect(text, contains('Cabinet'));
    expect(text, contains('Office'));
  });

  test('ks2 text lists finish sections', () {
    final project = Project(name: 'Office');
    final room = Room(
      name: 'Cabinet',
      walls: [
        [0, 0, 400, 0],
        [400, 0, 400, 300],
        [400, 300, 0, 300],
        [0, 300, 0, 0],
      ],
    );
    final text = buildKs2MaterialsText(
      project: project,
      room: room,
      stamp: DocumentationStamp(),
    );
    expect(text, contains('КС-2'));
    expect(text, contains('Площадь пола'));
  });
}
