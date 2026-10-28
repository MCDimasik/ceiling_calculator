import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/design_ceiling_features_baseline.dart';
import 'package:ceiling_calculator/domain/finish_design_baseline.dart';
import 'package:ceiling_calculator/domain/finish_model.dart';
import 'package:ceiling_calculator/domain/finish_quantities.dart';
import 'package:ceiling_calculator/domain/models.dart';

void main() {
  final rectWalls = [
    [0.0, 0.0, 600.0, 0.0],
    [600.0, 0.0, 600.0, 600.0],
    [600.0, 600.0, 0.0, 600.0],
    [0.0, 600.0, 0.0, 0.0],
  ];

  test('finishLayoutCountsForRoom matches individual counters', () {
    final room = Room(
      name: 'R',
      walls: rectWalls,
      layoutConfirmed: true,
      finishTileWidthCm: 60,
      finishTileHeightCm: 60,
    );
    final counts = finishLayoutCountsForRoom(room);
    expect(counts.floorBoards, floorBoardCountForRoom(room));
    expect(counts.ceilingTiles, ceilingLayoutTileCountForRoom(room));
    expect(counts.floorBoards, greaterThan(0));
    expect(counts.ceilingTiles, greaterThan(0));
  });

  test('FinishCalculator uses ceiling layout tile count when provided', () {
    final room = Room(name: 'R', walls: rectWalls, layoutConfirmed: true);
    final layoutCount = ceilingLayoutTileCountForRoom(room);
    final fromLayout = FinishCalculator.compute(
      walls: room.walls,
      heightCm: 270,
      openings: const [],
      ceilingCellCm: 60,
      ceilingLayoutTileCount: layoutCount,
    );
    expect(fromLayout.ceilingTiles, layoutCount);
    expect(layoutCount, greaterThan(0));
  });

  test('design ceiling features baseline snapshots guides and lights', () {
    final room = Room(
      name: 'R',
      walls: rectWalls,
      ceilingGuides: [
        {'axis': 'h', 'line': 1, 'kind': '3600'},
      ],
      lightFixtures: [
        [300, 300],
      ],
    );
    ensureDesignCeilingFeaturesBaseline(room);
    expect(readDesignCeilingGuides(room)?.length, 1);
    expect(readDesignLightFixtures(room)?.length, 1);

    room.ceilingGuides = [];
    room.lightFixtures = [];
    final (g, l) = ceilingFeaturesDelta(room);
    expect(g, 1);
    expect(l, 1);
    expect(formatCeilingFeaturesDeltaLabel(room), contains('Δ'));
  });

  test('design guide keys detect geometry mismatch', () {
    final room = Room(
      name: 'R',
      walls: rectWalls,
      ceilingGuides: [
        {'axis': 'h', 'line': 2, 'kind': '1200'},
      ],
    );
    ensureDesignCeilingFeaturesBaseline(room);
    room.ceilingGuides = [
      {'axis': 'h', 'line': 3, 'kind': '1200'},
    ];
    expect(designGuideKeysNotInFact(room), isNotEmpty);
    expect(factGuideKeys(room), isNotEmpty);
    final (g, _) = ceilingFeaturesDelta(room);
    expect(g, greaterThan(0));
  });
}
