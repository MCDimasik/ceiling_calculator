import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/floor_covering.dart';
import 'package:ceiling_calculator/domain/floor_layout.dart';

void main() {
  const walls = [
    [0.0, 0.0, 400.0, 0.0],
    [400.0, 0.0, 400.0, 300.0],
    [400.0, 300.0, 0.0, 300.0],
    [0.0, 300.0, 0.0, 0.0],
  ];

  test('legacy herringbone/chevron ids map to straight layout', () {
    expect(FloorLayingPatternX.parse('herringbone'), FloorLayingPattern.straight);
    expect(FloorLayingPatternX.parse('chevron'), FloorLayingPattern.straight);

    final legacy = FloorLayoutBuilder.build(
      walls: walls,
      covering: FloorCoveringKind.laminate,
      pattern: FloorLayingPatternX.parse('herringbone'),
      boardW: 19.2,
      boardL: 120,
      offsetX: 0,
      offsetY: 0,
    );
    final straight = FloorLayoutBuilder.build(
      walls: walls,
      covering: FloorCoveringKind.laminate,
      pattern: FloorLayingPattern.straight,
      boardW: 19.2,
      boardL: 120,
      offsetX: 0,
      offsetY: 0,
    );
    expect(legacy.fullCount, straight.fullCount);
    expect(legacy.cutCount, straight.cutCount);
  });

  test('90 degree rotation keeps room coverage', () {
    final base = FloorLayoutBuilder.build(
      walls: walls,
      covering: FloorCoveringKind.laminate,
      pattern: FloorLayingPattern.straight,
      boardW: 20,
      boardL: 120,
      offsetX: 0,
      offsetY: 0,
      rotationDeg: 0,
    );
    final rotated = FloorLayoutBuilder.build(
      walls: walls,
      covering: FloorCoveringKind.laminate,
      pattern: FloorLayingPattern.straight,
      boardW: 20,
      boardL: 120,
      offsetX: 0,
      offsetY: 0,
      rotationDeg: 90,
    );
    expect(rotated.boards, isNotEmpty);
    for (final b in rotated.boards) {
      expect(b.rotationRad, closeTo(math.pi / 2, 0.01));
    }
    expect(base.boards.first.widthCm, closeTo(120, 0.01));
    expect(base.boards.first.heightCm, closeTo(20, 0.01));
    expect(rotated.boards.first.widthCm, closeTo(120, 0.01));
    expect(rotated.boards.first.heightCm, closeTo(20, 0.01));
    expect(
      rotated.fullCount + rotated.cutCount,
      greaterThanOrEqualTo(base.fullCount + base.cutCount - 2),
    );
  });

  test('diagonal pattern rotates as a whole', () {
    final base = FloorLayoutBuilder.build(
      walls: walls,
      covering: FloorCoveringKind.laminate,
      pattern: FloorLayingPattern.diagonal,
      boardW: 20,
      boardL: 120,
      offsetX: 0,
      offsetY: 0,
      rotationDeg: 0,
    );
    final rotated = FloorLayoutBuilder.build(
      walls: walls,
      covering: FloorCoveringKind.laminate,
      pattern: FloorLayingPattern.diagonal,
      boardW: 20,
      boardL: 120,
      offsetX: 0,
      offsetY: 0,
      rotationDeg: 90,
    );
    expect(base.boards, isNotEmpty);
    expect(rotated.boards, isNotEmpty);
    final baseAng = base.boards.first.rotationRad;
    final rotAng = rotated.boards.first.rotationRad;
    expect(baseAng, closeTo(math.pi / 4, 0.01));
    expect(rotAng, closeTo(math.pi / 4 + math.pi / 2, 0.01));
  });
}
