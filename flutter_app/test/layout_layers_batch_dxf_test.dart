import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/dxf_export.dart';
import 'package:ceiling_calculator/domain/layout_layers.dart';
import 'package:ceiling_calculator/domain/models.dart';

void main() {
  final walls = [
    [0.0, 0.0, 600.0, 0.0],
    [600.0, 0.0, 600.0, 400.0],
    [600.0, 400.0, 0.0, 400.0],
    [0.0, 400.0, 0.0, 0.0],
  ];

  test('force-fit path: LayoutLayerVisibility dims persist in json', () {
    const layers = LayoutLayerVisibility(
      floor: true,
      notes: true,
      wallDims: false,
      tileDims: true,
    );
    final round = LayoutLayerVisibility.fromJson(layers.toJson());
    expect(round.floor, isTrue);
    expect(round.notes, isTrue);
    expect(round.wallDims, isFalse);
    expect(round.tileDims, isTrue);
  });

  test('batch-style DXF includes FLOOR NOTES DIMENSIONS from layer flags', () {
    final room = Room(
      name: 'R',
      walls: walls,
      documentationChecklistJson: {'notes': 'Поле'},
    );
    final project = Project(name: 'P', rooms: [room]);
    final grid = gridForDxfExport(room, project);
    final layers = const LayoutLayerVisibility(floor: true, notes: true, wallDims: true);
    final dxf = String.fromCharCodes(
      buildLayoutDxf(
        room: room,
        grid: grid,
        includeFloor: layers.floor,
        includeNotes: layers.notes,
        includeDimensions: layers.wallDims || layers.tileDims,
      ),
    );
    expect(dxf, contains('FLOOR'));
    expect(dxf, contains('NOTES'));
    expect(dxf, contains('DIMENSIONS'));
  });
}
