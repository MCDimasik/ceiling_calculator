import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/ceiling_guides.dart';
import 'package:ceiling_calculator/domain/project_materials.dart';
import 'package:ceiling_calculator/domain/models.dart';

void main() {
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
      anchorAlongCm: 180,
    );
    expect(pieces.length, 2);
    expect(pieces.first.x1, closeTo(0, 0.01));
    expect(pieces.last.x2, closeTo(400, 0.01));
    expect(pieces[0].x2 - pieces[0].x1, closeTo(180, 0.01));
    expect(pieces[1].x2 - pieces[1].x1, closeTo(220, 0.01));
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
      anchorAlongCm: 80, // offset 20 + index 1 × 60
    );
    expect(pieces.isNotEmpty, isTrue);
    expect(pieces.first.x1, closeTo(0, 0.01));
    expect(pieces.last.x2, closeTo(400, 0.01));
    final covered = pieces.fold<double>(0, (s, p) => s + (p.x2 - p.x1));
    expect(covered, closeTo(400, 0.01));
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

  test('packGuidePurchaseCount packs short scraps into fewer stock lengths', () {
    final scraps = [
      const GuideDrawSegment(x1: 0, y1: 0, x2: 100, y2: 0, isPrimary: true),
      const GuideDrawSegment(x1: 0, y1: 0, x2: 120, y2: 0, isPrimary: true),
      const GuideDrawSegment(x1: 0, y1: 0, x2: 80, y2: 0, isPrimary: true),
    ];
    // 300 cm of scrap / 360 → 1 stock bar (not 3).
    expect(packGuidePurchaseCount(scraps, 360), 1);

    final mixed = [
      const GuideDrawSegment(x1: 0, y1: 0, x2: 360, y2: 0, isPrimary: true),
      const GuideDrawSegment(x1: 0, y1: 0, x2: 40, y2: 0, isPrimary: true),
      const GuideDrawSegment(x1: 0, y1: 0, x2: 40, y2: 0, isPrimary: true),
    ];
    expect(packGuidePurchaseCount(mixed, 360), 2);
  });
}
