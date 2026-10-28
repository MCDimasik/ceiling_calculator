import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/documentation_model.dart';

void main() {
  test('RoomExportTemplates round-trip in checklist JSON', () {
    final templates = RoomExportTemplates(
      ks2TemplatePath: '/tmp/ks2.json',
      actHiddenTemplatePath: '/tmp/act.json',
    );
    final merged = RoomExportTemplates.mergeIntoChecklist(
      {'accepted': true, 'notes': 'n'},
      templates,
    );
    expect(merged['accepted'], isTrue);
    expect(merged['notes'], 'n');
    final raw = merged['export_templates'] as Map;
    expect(raw['ks2'], '/tmp/ks2.json');
    expect(raw['act_hidden'], '/tmp/act.json');

    final parsed = RoomExportTemplates.fromChecklistJson(merged);
    expect(parsed.ks2TemplatePath, '/tmp/ks2.json');
    expect(parsed.actHiddenTemplatePath, '/tmp/act.json');
    expect(parsed.vedomostTemplatePath, isNull);
  });

  test('roomChecklistJsonForSave preserves export_templates', () {
    final checklist = RoomDocumentationChecklist(notes: 'updated');
    final existing = {
      'notes': 'old',
      'export_templates': {'ks2': '/room/ks2.json'},
    };
    final saved = roomChecklistJsonForSave(checklist, existing);
    expect(saved['notes'], 'updated');
    expect(
      (saved['export_templates'] as Map)['ks2'],
      '/room/ks2.json',
    );
  });

  test('clearing templates removes export_templates key', () {
    final merged = RoomExportTemplates.mergeIntoChecklist(
      {'accepted': false},
      RoomExportTemplates(ks2TemplatePath: '/x.json'),
    );
    expect(merged.containsKey('export_templates'), isTrue);
    final cleared = RoomExportTemplates.mergeIntoChecklist(
      merged,
      RoomExportTemplates(),
    );
    expect(cleared.containsKey('export_templates'), isFalse);
  });
}
