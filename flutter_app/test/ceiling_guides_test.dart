import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/ceiling_guides.dart';
import 'package:ceiling_calculator/domain/project_materials.dart';
import 'package:ceiling_calculator/domain/models.dart';

void main() {
  test('armstrong ignores grilyato guide marks on layout', () {
    final room = Room(
      name: 'R',
      walls: [
        [0, 0, 400, 0],
        [400, 0, 400, 300],
        [400, 300, 0, 300],
        [0, 300, 0, 0],
      ],
      gridOffsetX: 0,
      gridOffsetY: 0,
      ceilingGuides: [
        {'axis': 'h', 'line': 0, 'kind': '3600'},
        {'axis': 'h', 'line': 1, 'kind': '2400'},
      ],
    );
    final project = Project(name: 'P', materialsCeiling: 'Армстронг');
    final mats = calculateRoomMaterials(room, project);
    expect(mats.keys.any((k) => k.contains('2400')), isFalse);
    expect(mats.keys.any((k) => k.startsWith('Профиль')), isFalse);
    expect(mats.keys.any((k) => k == 'Соединитель'), isFalse);
  });

  test('grilyato classic profiles follow cell size from UI config', () {
    final room = Room(
      name: 'R',
      walls: [
        [0, 0, 400, 0],
        [400, 0, 400, 300],
        [400, 300, 0, 300],
        [0, 300, 0, 0],
      ],
    );
    final project = Project(name: 'P', materialsCeiling: 'Грильято', materialsCell: '100x100');
    final ui75 = const MaterialsUiConfig(
      ceiling: 'Грильято',
      susp: 'Подвес 0,5',
      cell: '75x75',
    );
    final mats = calculateRoomMaterials(room, project, ui: ui75);
    expect(mats['Профиль Папа (75x75)'], isNotNull);
    expect(mats['Профиль Папа (50x50)'], isNull);
    expect(mats.keys.any((k) => k.contains('3600')), isFalse);
    expect(mats.keys.any((k) => k.contains('Армстронг')), isFalse);
  });

  test('project aggregate uses header UI and collapses suspension keys', () {
    final roomA = Room(
      id: 1,
      name: 'A',
      walls: [
        [0, 0, 400, 0],
        [400, 0, 400, 300],
        [400, 300, 0, 300],
        [0, 300, 0, 0],
      ],
      materialsOverride: true,
      materialsSusp: 'Подвес 0,5',
    );
    final roomB = Room(
      id: 2,
      name: 'B',
      walls: [
        [0, 0, 300, 0],
        [300, 0, 300, 250],
        [300, 250, 0, 250],
        [0, 250, 0, 0],
      ],
    );
    final project = Project(
      name: 'P',
      materialsCeiling: 'Армстронг',
      materialsSusp: 'Подвес 0,5',
      rooms: [roomA, roomB],
    );
    const ui1 = MaterialsUiConfig(
      ceiling: 'Армстронг',
      susp: 'Подвес 1',
      cell: '50x50',
    );
    final (totals, _, _) = aggregateCeilingTotals(project, ui: ui1);
    // Override room keeps its suspension size; others follow header UI.
    expect(totals.containsKey('Подвес (0,5)'), isTrue);
    expect(totals.containsKey('Подвес (1)'), isTrue);
    expect(totals.keys.any((k) => k.startsWith('Подвес')), isTrue);
  });

  test('project aggregate keeps override room Grilyato lines under Armstrong UI', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];
    final roomA = Room(id: 1, name: 'A', walls: walls);
    final roomB = Room(
      id: 2,
      name: 'B',
      walls: walls,
      materialsOverride: true,
      materialsCeiling: 'Грильято',
      materialsCell: '50x50',
      materialsSusp: 'Подвес 1',
    );
    final project = Project(
      name: 'P',
      materialsCeiling: 'Армстронг',
      materialsSusp: 'Подвес 0,5',
      rooms: [roomA, roomB],
    );
    const ui = MaterialsUiConfig(
      ceiling: 'Армстронг',
      susp: 'Подвес 0,5',
      cell: '100x100',
    );
    final (totals, _, _) = aggregateCeilingTotals(project, ui: ui);
    expect(totals['Направляющая 3600'], greaterThan(0));
    expect(totals['Направляющая 2400'], greaterThan(0));
    expect(totals['Профиль Папа (50x50)'], greaterThan(0));
    expect(totals['Соединитель'], greaterThan(0));
    expect(totals['Подвес (0,5)'], greaterThan(0));
    expect(totals['Подвес (1)'], greaterThan(0));
  });

  test('suspension line replaces on type change', () {
    final room = Room(
      name: 'R',
      walls: [
        [0, 0, 400, 0],
        [400, 0, 400, 300],
        [400, 300, 0, 300],
        [0, 300, 0, 0],
      ],
      ceilingGuides: [
        {'axis': 'h', 'line': 0, 'kind': '3600'},
      ],
    );
    final project = Project(name: 'P', materialsCeiling: 'Армстронг', materialsSusp: 'Подвес 0,5');
    final ui1 = const MaterialsUiConfig(
      ceiling: 'Армстронг',
      susp: 'Подвес 1',
      cell: '50x50',
    );
    final mats = calculateRoomMaterials(room, project, ui: ui1);
    expect(mats.keys.where((k) => k.startsWith('Подвес')).length, 1);
    expect(mats.containsKey('Подвес (1)'), isTrue);
    expect(mats.containsKey('Подвес (0,5)'), isFalse);
  });

  test('guide marks override formula counts for 4x3 m room', () {
    final room = Room(
      name: 'R',
      walls: [
        [0, 0, 400, 0],
        [400, 0, 400, 300],
        [400, 300, 0, 300],
        [0, 300, 0, 0],
      ],
      gridOffsetX: 0,
      gridOffsetY: 0,
      ceilingGuides: [
        {'axis': 'h', 'line': 0, 'kind': '3600'},
        {'axis': 'h', 'line': 1, 'kind': '3600'},
        {'axis': 'v', 'line': 0, 'kind': '1200'},
      ],
    );
    final project = Project(name: 'P');
    final mats = calculateRoomMaterials(room, project);
    expect(mats['Направляющая 3600'], isNotNull);
    expect(mats['Направляющая 1200'], isNotNull);
    expect(mats.keys.any((k) => k.startsWith('Подвес')), isTrue);
  });

  test('small-room marks without 3600 do not keep formula 3600', () {
    // ~1.8×1.2 m — typical case where only 1200/600 are placed.
    final room = Room(
      name: 'Малая',
      walls: [
        [0, 0, 180, 0],
        [180, 0, 180, 120],
        [180, 120, 0, 120],
        [0, 120, 0, 0],
      ],
      gridOffsetX: 0,
      gridOffsetY: 0,
      ceilingGuides: [
        {'axis': 'h', 'line': 0, 'kind': '1200'},
        {'axis': 'h', 'line': 1, 'kind': '1200'},
        {'axis': 'v', 'line': 0, 'kind': '600'},
        {'axis': 'v', 'line': 1, 'kind': '600'},
        {'axis': 'v', 'line': 2, 'kind': '600'},
      ],
    );
    final project = Project(name: 'Область', materialsCeiling: 'Армстронг');
    final mats = calculateRoomMaterials(room, project);
    expect(mats.containsKey('Направляющая 3600'), isFalse);
    expect(mats['Направляющая 1200'], greaterThan(0));
    expect(mats['Направляющая 600'], greaterThan(0));
  });

  test('empty guides auto-build frame instead of area formula', () {
    final room = Room(
      name: 'R',
      walls: [
        [0, 0, 400, 0],
        [400, 0, 400, 300],
        [400, 300, 0, 300],
        [0, 300, 0, 0],
      ],
    );
    final project = Project(name: 'P', materialsCeiling: 'Армстронг');
    final mats = calculateRoomMaterials(room, project);
    final auto = countGuidesFromMarks(
      autoGuideMarksForRoom(
        walls: room.walls,
        offsetX: 0,
        offsetY: 0,
        cellSize: layoutTileCm,
        ceilingLabel: 'Армстронг',
      ),
      room.walls,
      offsetX: 0,
      offsetY: 0,
      cellSize: layoutTileCm,
    )!;
    expect(mats['Направляющая 3600'], auto['Направляющая 3600']);
    expect(mats['Направляющая 1200'], auto['Направляющая 1200']);
    expect(mats['Направляющая 600'], auto['Направляющая 600']);
    // Area formula for 12 m²: 3×3600 / 17×1200 / 17×600. Scrap-join packing
    // can make 3600 match by chance; 1200/600 from the auto frame still differ.
    expect(mats['Направляющая 1200'], isNot(((12.0 * 1.68) / 1.2).ceil()));
    expect(mats['Направляющая 600'], isNot(((12.0 * 0.85) / 0.6).ceil()));
  });

  test('countGuidesFromMarks sums pieces along marked lines', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];
    final marks = [
      CeilingGuideMark(
        axis: GuideAxis.horizontal,
        lineIndex: 2,
        kind: GuideKind.g3600,
        anchorAlongIndex: 3,
      ),
    ];
    final counts = countGuidesFromMarks(
      marks,
      walls,
      offsetX: 0,
      offsetY: 0,
      cellSize: 60,
    )!;
    expect(counts['Направляющая 3600'], 2);
  });

  test('legacy pos cm migrates to grid line index', () {
    final mark = CeilingGuideMark.fromJson(
      {'axis': 'h', 'pos': 120, 'kind': '3600'},
      offsetY: 0,
      cellSize: 60,
    );
    expect(mark?.lineIndex, 2);
  });

  test('snapGuideLineIndex snaps to wall-aligned grid line', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];
    // Grid starts at wall (offset 0): tap near y=0 → line index 0, not 1.
    final atWall = snapGuideLineIndex(
      axis: GuideAxis.horizontal,
      worldCoord: 8,
      offset: 0,
      cellSize: 60,
      walls: walls,
    );
    expect(atWall, 0);
    expect(atWall * 60, 0);

    final next = snapGuideLineIndex(
      axis: GuideAxis.horizontal,
      worldCoord: 55,
      offset: 0,
      cellSize: 60,
      walls: walls,
    );
    expect(next, 1);
  });

  test('guide profile pieces fill wall-to-wall and clip short ends', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];
    final mark = CeilingGuideMark(
      axis: GuideAxis.horizontal,
      lineIndex: 2,
      kind: GuideKind.g3600,
      anchorAlongIndex: 3,
    );
    final pieces = guideProfilePieceSegments(
      mark,
      walls,
      offsetX: 0,
      offsetY: 0,
      cellSize: 60,
      coordCm: 120,
    );
    // Tile from the wall: full 360 + remainder 40 (anchor phase ignored).
    expect(pieces.length, 2);
    expect(pieces.first.x1, closeTo(0, 0.01));
    expect(pieces.last.x2, closeTo(400, 0.01));
    expect(pieces[0].x2 - pieces[0].x1, closeTo(360, 0.01));
    expect(pieces[1].x2 - pieces[1].x1, closeTo(40, 0.01));
  });

  test('guide pieces still fill walls after grid phase shift', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];
    final mark = CeilingGuideMark(
      axis: GuideAxis.horizontal,
      lineIndex: 2,
      kind: GuideKind.g3600,
      anchorAlongIndex: 1,
    );
    final pieces = guideProfilePieceSegments(
      mark,
      walls,
      offsetX: 20,
      offsetY: 0,
      cellSize: 60,
      coordCm: 120,
    );
    expect(pieces.isNotEmpty, isTrue);
    expect(pieces.first.x1, closeTo(0, 0.01));
    expect(pieces.last.x2, closeTo(400, 0.01));
    final covered = pieces.fold<double>(0, (s, p) => s + (p.x2 - p.x1));
    expect(covered, closeTo(400, 0.01));
    expect(pieces[0].x2 - pieces[0].x1, closeTo(360, 0.01));
    expect(pieces[1].x2 - pieces[1].x1, closeTo(40, 0.01));
  });

  test('guide draw segments mark lead piece along the run', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];
    final mark = CeilingGuideMark(
      axis: GuideAxis.horizontal,
      lineIndex: 2,
      kind: GuideKind.g3600,
    );
    final segs = guideDrawSegments(
      mark,
      walls,
      offsetX: 0,
      offsetY: 0,
      cellSize: 60,
    );
    expect(segs.where((s) => s.isPrimary).length, 1);
    expect(segs.where((s) => !s.isPrimary).length, 1);
    final primary = segs.firstWhere((s) => s.isPrimary);
    expect(primary.x2 - primary.x1, closeTo(360, 0.01));
  });

  test('proposeArmstrongFrame builds 3600 / 1200 / 600 grid from seed', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];
    final seed = CeilingGuideMark(
      axis: GuideAxis.horizontal,
      lineIndex: 2,
      kind: GuideKind.g3600,
      anchorAlongIndex: 3,
    );
    final frame = proposeArmstrongFrame(
      seed: seed,
      offsetX: 0,
      offsetY: 0,
      cellSize: 60,
      walls: walls,
    );
    expect(frame.any((g) => g.kind == GuideKind.g3600), isTrue);
    expect(frame.any((g) => g.kind == GuideKind.g1200), isTrue);
    expect(frame.any((g) => g.kind == GuideKind.g600), isTrue);

    final mains = frame.where((g) => g.kind == GuideKind.g3600).toList();
    for (final m in mains) {
      expect(m.axis, GuideAxis.horizontal);
      expect((m.lineIndex - 2) % 2, 0);
    }
    final crosses = frame.where((g) => g.kind == GuideKind.g1200).toList();
    expect(crosses.every((g) => g.axis == GuideAxis.vertical), isTrue);
  });

  test('grilyato classic 50x50 uses same carrier as Armstrong with 2400 mains', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];
    final seed = CeilingGuideMark(
      axis: GuideAxis.horizontal,
      lineIndex: 2,
      kind: GuideKind.g2400,
      anchorAlongIndex: 1,
    );
    final frame = proposeCeilingFrame(
      template: CeilingFrameTemplate.grilyatoClassic,
      seed: seed,
      offsetX: 0,
      offsetY: 0,
      cellSize: 60,
      walls: walls,
      cellSizeLabel: '50x50',
    );
    expect(frame.any((g) => g.kind == GuideKind.g2400), isTrue);
    expect(frame.any((g) => g.kind == GuideKind.g1200), isTrue);
    expect(frame.any((g) => g.kind == GuideKind.g600), isTrue);
    final mains = frame.where((g) => g.kind == GuideKind.g2400);
    for (final m in mains) {
      expect((m.lineIndex - 2) % 2, 0);
    }
  });

  test('grilyato classic 100x100 uses 2400 every 1200 with 1200 crosses', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];
    final seed = CeilingGuideMark(
      axis: GuideAxis.horizontal,
      lineIndex: 2,
      kind: GuideKind.g2400,
      anchorAlongIndex: 1,
    );
    final frame = proposeCeilingFrame(
      template: CeilingFrameTemplate.grilyatoClassic,
      seed: seed,
      offsetX: 0,
      offsetY: 0,
      cellSize: 60,
      walls: walls,
      cellSizeLabel: '100x100',
    );
    expect(frame.any((g) => g.kind == GuideKind.g2400), isTrue);
    expect(frame.any((g) => g.kind == GuideKind.g1200), isTrue);
    expect(frame.any((g) => g.kind == GuideKind.g600), isTrue);
  });

  test('packGuidePurchaseCount joins one-lock remnants with 20+20 margin', () {
    // Three 200 cm spans from 3600: 2 buys → remnants 160+160; 160+160−40 ≥ 200.
    final threeSpans = [
      const GuideDrawSegment(x1: 0, y1: 0, x2: 200, y2: 0, isPrimary: true),
      const GuideDrawSegment(x1: 0, y1: 20, x2: 200, y2: 20, isPrimary: true),
      const GuideDrawSegment(x1: 0, y1: 40, x2: 200, y2: 40, isPrimary: true),
    ];
    expect(packGuidePurchaseCount(threeSpans, 360), 2);

    // Two 100 cm remnants cannot cover 200 cm after −40 join margin.
    final noJoinMargin = [
      const GuideDrawSegment(x1: 0, y1: 0, x2: 260, y2: 0, isPrimary: true),
      const GuideDrawSegment(x1: 0, y1: 20, x2: 260, y2: 20, isPrimary: true),
      const GuideDrawSegment(x1: 0, y1: 40, x2: 200, y2: 40, isPrimary: true),
    ];
    // Buy1 → rem 100; buy2 → rem 100; 100+100−40=160 < 200 → buy3. Total 3.
    expect(packGuidePurchaseCount(noJoinMargin, 360), 3);

    // One bar yields at most two one-lock shorts (both ends); middle is scrap.
    final scraps = [
      const GuideDrawSegment(x1: 0, y1: 0, x2: 100, y2: 0, isPrimary: true),
      const GuideDrawSegment(x1: 0, y1: 0, x2: 120, y2: 0, isPrimary: true),
      const GuideDrawSegment(x1: 0, y1: 0, x2: 80, y2: 0, isPrimary: true),
    ];
    // 120: buy, rem 240; 100 from rem (leftover scrap); 80: buy. Total 2.
    expect(packGuidePurchaseCount(scraps, 360), 2);

    final mixed = [
      const GuideDrawSegment(x1: 0, y1: 0, x2: 360, y2: 0, isPrimary: true),
      const GuideDrawSegment(x1: 0, y1: 0, x2: 40, y2: 0, isPrimary: true),
      const GuideDrawSegment(x1: 0, y1: 0, x2: 40, y2: 0, isPrimary: true),
    ];
    // Full + short: buy full; first 40 buys and banks 320; second 40 from remnant.
    expect(packGuidePurchaseCount(mixed, 360), 2);

    final crumbs = [
      const GuideDrawSegment(x1: 0, y1: 0, x2: 3, y2: 0, isPrimary: true),
      const GuideDrawSegment(x1: 0, y1: 0, x2: 200, y2: 0, isPrimary: true),
    ];
    expect(packGuidePurchaseCount(crumbs, 360), 1);

    // Five 65 cm ends from 3600: at most 2 per bar → 3 purchases (not 1 by length).
    final fiveEnds = List.generate(
      5,
      (i) => GuideDrawSegment(
        x1: 0,
        y1: i * 10.0,
        x2: 65,
        y2: i * 10.0,
        isPrimary: true,
      ),
    );
    expect(packGuidePurchaseCount(fiveEnds, 360), 3);

    // Office-15 style: 5×360 + 5×65 → 5 full + 3 for ends = 8.
    final officeMains = <GuideDrawSegment>[
      for (var i = 0; i < 5; i++) ...[
        GuideDrawSegment(
          x1: 0,
          y1: i * 20.0,
          x2: 360,
          y2: i * 20.0,
          isPrimary: true,
        ),
        GuideDrawSegment(
          x1: 360,
          y1: i * 20.0,
          x2: 425,
          y2: i * 20.0,
          isPrimary: true,
        ),
      ],
    ];
    expect(packGuidePurchaseCount(officeMains, 360), 8);

    expect(guideLockTrimCm, 10);
    expect(guideJoinMarginCm, 20);
    expect(GuideKind.g3600.lengthCm - 2 * guideLockTrimCm, 340);
  });

  test('auto frame skips carrier lines on room walls', () {
    final walls = [
      [0.0, 0.0, 425.0, 0.0],
      [425.0, 0.0, 425.0, 600.0],
      [425.0, 600.0, 0.0, 600.0],
      [0.0, 600.0, 0.0, 0.0],
    ];
    final frame = autoGuideMarksForRoom(
      walls: walls,
      offsetX: 5,
      offsetY: 0,
      cellSize: layoutTileCm,
      ceilingLabel: 'Армстронг',
    );
    for (final g in frame) {
      final coord = g.axis == GuideAxis.horizontal
          ? 0 + g.lineIndex * layoutTileCm
          : 5 + g.lineIndex * layoutTileCm;
      if (g.axis == GuideAxis.horizontal) {
        expect(coord, isNot(closeTo(0, 1)));
        expect(coord, isNot(closeTo(600, 1)));
      } else {
        expect(coord, isNot(closeTo(0, 1)));
        expect(coord, isNot(closeTo(425, 1)));
      }
    }
    expect(frame.any((g) => g.kind == GuideKind.g3600), isTrue);
  });
}
