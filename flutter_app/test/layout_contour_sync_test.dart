import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/layout_contour_sync.dart';
import 'package:ceiling_calculator/domain/models.dart';

void main() {
  final big = [
    [0.0, 0.0, 600.0, 0.0],
    [600.0, 0.0, 600.0, 400.0],
    [600.0, 400.0, 0.0, 400.0],
    [0.0, 400.0, 0.0, 0.0],
  ];
  final small = [
    [0.0, 0.0, 200.0, 0.0],
    [200.0, 0.0, 200.0, 200.0],
    [200.0, 200.0, 0.0, 200.0],
    [0.0, 200.0, 0.0, 0.0],
  ];

  test('syncLayoutFeaturesToContour drops lights outside new walls', () {
    final room = Room(
      name: 'R',
      walls: big,
      gridOffsetX: 0,
      gridOffsetY: 0,
      lightFixtures: [
        [1, 1],
        [8, 5], // far outside small room
      ],
      ceilingGuides: [
        {'axis': 'h', 'line': 1, 'kind': '3600'},
        {'axis': 'h', 'line': 20, 'kind': '1200'}, // far outside
      ],
    );
    room.walls = small;
    final sync = syncLayoutFeaturesToContour(room);
    expect(sync.removedLights, greaterThan(0));
    expect(room.lightFixtures.every((f) => f[0] < 5 && f[1] < 5), isTrue);
    expect(sync.removedGuides, greaterThan(0));
    expect(room.ceilingGuides.length, lessThan(2));
  });

  test('syncLayoutFeaturesToContour clears features on empty contour', () {
    final room = Room(
      name: 'R',
      walls: big,
      lightFixtures: [
        [1, 1],
      ],
      ceilingGuides: [
        {'axis': 'h', 'line': 1, 'kind': '3600'},
      ],
      layoutConfirmed: true,
    );
    room.walls = [];
    final sync = syncLayoutFeaturesToContour(room);
    expect(sync.removedLights, 1);
    expect(sync.removedGuides, 1);
    expect(sync.clearedLayoutConfirm, isTrue);
    expect(room.lightFixtures, isEmpty);
    expect(room.ceilingGuides, isEmpty);
    expect(room.layoutConfirmed, isFalse);
  });

  test('syncLayoutFeaturesToContour clears on open (non-closed) contour', () {
    final open = [
      [0.0, 0.0, 600.0, 0.0],
      [600.0, 0.0, 600.0, 400.0],
      [600.0, 400.0, 0.0, 400.0],
      // missing close to start
    ];
    final room = Room(
      name: 'R',
      walls: open,
      lightFixtures: [
        [1, 1],
      ],
      ceilingGuides: [
        {'axis': 'h', 'line': 1, 'kind': '3600'},
      ],
      layoutConfirmed: true,
    );
    expect(room.hasLayout, isFalse);
    final sync = syncLayoutFeaturesToContour(room);
    expect(sync.clearedLayoutConfirm, isTrue);
    expect(room.lightFixtures, isEmpty);
    expect(room.ceilingGuides, isEmpty);
    expect(room.layoutConfirmed, isFalse);
  });

  test('syncLayoutFeaturesToContour no-op when features fit', () {
    final room = Room(
      name: 'R',
      walls: big,
      lightFixtures: [
        [1, 1],
      ],
      ceilingGuides: [
        {'axis': 'h', 'line': 1, 'kind': '3600'},
      ],
    );
    final sync = syncLayoutFeaturesToContour(room);
    expect(sync.changed, isFalse);
    expect(room.lightFixtures, hasLength(1));
    expect(room.ceilingGuides, hasLength(1));
  });
}
