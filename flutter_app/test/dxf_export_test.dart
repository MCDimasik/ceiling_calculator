import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/documentation_model.dart';
import 'package:ceiling_calculator/domain/dxf_export.dart';
import 'package:ceiling_calculator/domain/models.dart';

void main() {
  final walls = [
    [0.0, 0.0, 600.0, 0.0],
    [600.0, 0.0, 600.0, 400.0],
    [600.0, 400.0, 0.0, 400.0],
    [0.0, 400.0, 0.0, 0.0],
  ];

  test('buildLayoutDxf emits wall, grid, guide and light entities', () {
    final room = Room(
      name: 'R',
      walls: walls,
      gridOffsetX: 0,
      gridOffsetY: 0,
      ceilingGuides: [
        {
          'axis': 'h',
          'line': 2,
          'anchor': 1,
          'kind': '3600',
        },
      ],
      lightFixtures: [
        [1, 1],
      ],
    );
    final project = Project(name: 'P', rooms: [room]);
    final grid = gridForDxfExport(room, project);
    final dxf = String.fromCharCodes(buildLayoutDxf(room: room, grid: grid));
    expect(dxf, contains('SECTION'));
    expect(dxf, contains('WALLS'));
    expect(dxf, contains('GRID'));
    expect(dxf, contains('GUIDES'));
    expect(dxf, contains('LIGHTS'));
    expect(dxf, contains('CIRCLE'));
    expect(dxf, contains('LINE'));
    expect(dxf, contains('EOF'));
  });

  test('buildLayoutDxf optional FLOOR NOTES DIMENSIONS layers', () {
    final room = Room(
      name: 'R',
      walls: walls,
      documentationChecklistJson: RoomDocumentationChecklist(notes: 'Полевая заметка').toJson(),
    );
    final project = Project(name: 'P', rooms: [room]);
    final grid = gridForDxfExport(room, project);
    final dxf = String.fromCharCodes(
      buildLayoutDxf(
        room: room,
        grid: grid,
        includeFloor: true,
        includeNotes: true,
        includeDimensions: true,
      ),
    );
    expect(dxf, contains('FLOOR'));
    expect(dxf, contains('NOTES'));
    expect(dxf, contains('DIMENSIONS'));
  });
}
