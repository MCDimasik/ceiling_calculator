import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'ceiling_grid.dart';
import 'ceiling_guides.dart';
import 'documentation_model.dart';
import 'floor_covering.dart';
import 'floor_layout.dart';
import 'models.dart';
import 'project_materials.dart';

/// Minimal ASCII DXF: walls, grid, guides, lights, floor, notes, dimensions (cm → mm).
Uint8List buildLayoutDxf({
  required Room room,
  required CeilingGrid grid,
  bool includeGrid = true,
  bool includeWalls = true,
  bool includeGuides = true,
  bool includeLights = true,
  bool includeFloor = false,
  bool includeNotes = false,
  bool includeDimensions = false,
}) {
  final lines = <String>[];
  void entity(String type, Map<String, Object> pairs) {
    lines.add('0');
    lines.add(type);
    for (final e in pairs.entries) {
      lines.add(e.key);
      lines.add('${e.value}');
    }
  }

  lines.add('0');
  lines.add('SECTION');
  lines.add('2');
  lines.add('HEADER');
  lines.add('9');
  lines.add('\$INSUNITS');
  lines.add('70');
  lines.add('4'); // millimeters — values below are cm × 10
  lines.add('0');
  lines.add('ENDSEC');
  lines.add('0');
  lines.add('SECTION');
  lines.add('2');
  lines.add('ENTITIES');

  double u(double cm) => cm * 10;

  if (includeWalls) {
    for (final w in room.walls) {
      entity('LINE', {
        '8': 'WALLS',
        '10': u(w[0]),
        '20': u(w[1]),
        '11': u(w[2]),
        '21': u(w[3]),
      });
    }
  }

  final cell = grid.cellSizeCm;
  final ox = room.gridOffsetX.toDouble();
  final oy = room.gridOffsetY.toDouble();

  if (includeGrid) {
    for (final c in grid.cells) {
      if (c.kind == CellKind.outside) continue;
      final x0 = c.xCm + grid.offsetXCm;
      final y0 = c.yCm + grid.offsetYCm;
      final x1 = x0 + cell;
      final y1 = y0 + cell;
      entity('LINE', {'8': 'GRID', '10': u(x0), '20': u(y0), '11': u(x1), '21': u(y0)});
      entity('LINE', {'8': 'GRID', '10': u(x1), '20': u(y0), '11': u(x1), '21': u(y1)});
      entity('LINE', {'8': 'GRID', '10': u(x1), '20': u(y1), '11': u(x0), '21': u(y1)});
      entity('LINE', {'8': 'GRID', '10': u(x0), '20': u(y1), '11': u(x0), '21': u(y0)});
    }
  }

  if (includeGuides && room.ceilingGuides.isNotEmpty) {
    final marks = parseCeilingGuidesWithLegacyAnchor(
      room.ceilingGuides,
      room.walls,
      offsetX: ox,
      offsetY: oy,
      cellSize: cell,
    );
    for (final mark in marks) {
      final segs = guideProfilePieceSegments(
        mark,
        room.walls,
        offsetX: ox,
        offsetY: oy,
        cellSize: cell,
      );
      for (final s in segs) {
        entity('LINE', {
          '8': s.isPrimary ? 'GUIDES_PRIMARY' : 'GUIDES',
          '10': u(s.x1),
          '20': u(s.y1),
          '11': u(s.x2),
          '21': u(s.y2),
        });
      }
    }
  }

  if (includeLights) {
    final radius = cell * 0.15;
    for (final f in room.lightFixtures) {
      if (f.length < 2) continue;
      final cx = ox + f[0] * cell + cell / 2;
      final cy = oy + f[1] * cell + cell / 2;
      entity('CIRCLE', {
        '8': 'LIGHTS',
        '10': u(cx),
        '20': u(cy),
        '40': u(radius),
      });
    }
  }

  if (includeFloor && room.hasLayout) {
    final covering = FloorCoveringKindX.parse(room.floorCoveringKind);
    final pattern = FloorLayingPatternX.parse(room.floorLayingPattern);
    final layout = FloorLayoutBuilder.build(
      walls: room.walls,
      covering: covering,
      pattern: pattern,
      boardW: room.finishTileWidthCm,
      boardL: room.finishTileHeightCm,
      offsetX: room.floorGridOffsetX.toDouble(),
      offsetY: room.floorGridOffsetY.toDouble(),
      rotationDeg: room.floorLayoutRotationDeg,
    );
    for (final t in layout.boards) {
      final x0 = t.cxCm - t.widthCm / 2;
      final y0 = t.cyCm - t.heightCm / 2;
      final x1 = t.cxCm + t.widthCm / 2;
      final y1 = t.cyCm + t.heightCm / 2;
      entity('LINE', {
        '8': 'FLOOR',
        '10': u(x0),
        '20': u(y0),
        '11': u(x1),
        '21': u(y0),
      });
      entity('LINE', {
        '8': 'FLOOR',
        '10': u(x1),
        '20': u(y0),
        '11': u(x1),
        '21': u(y1),
      });
      entity('LINE', {
        '8': 'FLOOR',
        '10': u(x1),
        '20': u(y1),
        '11': u(x0),
        '21': u(y1),
      });
      entity('LINE', {
        '8': 'FLOOR',
        '10': u(x0),
        '20': u(y1),
        '11': u(x0),
        '21': u(y0),
      });
    }
  }

  if (includeNotes) {
    final notes = RoomDocumentationChecklist.fromJson(room.documentationChecklistJson).notes.trim();
    if (notes.isNotEmpty) {
      double minX = room.walls.first[0];
      double maxY = room.walls.first[1];
      for (final w in room.walls) {
        minX = math.min(minX, math.min(w[0], w[2]));
        maxY = math.max(maxY, math.max(w[1], w[3]));
      }
      final short = notes.length > 80 ? '${notes.substring(0, 77)}…' : notes;
      entity('TEXT', {
        '8': 'NOTES',
        '10': u(minX),
        '20': u(maxY + 20),
        '40': u(8),
        '1': short.replaceAll('\n', ' '),
      });
    }
  }

  if (includeDimensions) {
    for (final w in room.walls) {
      final len = math.sqrt(math.pow(w[2] - w[0], 2) + math.pow(w[3] - w[1], 2));
      final mx = (w[0] + w[2]) / 2;
      final my = (w[1] + w[3]) / 2;
      entity('LINE', {
        '8': 'DIMENSIONS',
        '10': u(w[0]),
        '20': u(w[1]),
        '11': u(w[2]),
        '21': u(w[3]),
      });
      entity('TEXT', {
        '8': 'DIMENSIONS',
        '10': u(mx),
        '20': u(my + 8),
        '40': u(6),
        '1': len.toStringAsFixed(0),
      });
    }
  }

  lines.add('0');
  lines.add('ENDSEC');
  lines.add('0');
  lines.add('EOF');
  return Uint8List.fromList(utf8.encode(lines.join('\n')));
}

/// Build grid from room state for DXF export.
CeilingGrid gridForDxfExport(Room room, Project project) {
  final grid = CeilingGrid();
  final (ceiling, _, cell) = roomEffectiveConfig(room, project);
  if (ceiling == 'Грильято' || ceiling == 'GL') {
    grid.cellSizeCm = layoutTileCm;
  }
  grid.offsetXCm = room.gridOffsetX.toDouble();
  grid.offsetYCm = room.gridOffsetY.toDouble();
  final lightIds = room.lightFixtures
      .where((f) => f.length >= 2)
      .map((f) => '${f[0]}:${f[1]}')
      .toSet();
  grid.rebuild(
    roomPoints: pointsFromWalls(room.walls),
    walls: room.walls,
    lightIds: lightIds,
  );
  return grid;
}

String layoutDxfFilename(Project project, Room room) =>
    '${project.name}_${room.name}_layout.dxf'.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
