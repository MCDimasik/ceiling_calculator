import 'package:ceiling_calculator/domain/special_space.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StairwellParams', () {
    test('U-landing box × storey height', () {
      final s = StairwellParams(
        plan: StairPlanKind.uLanding,
        inputFocus: StairInputFocus.boxAndStoreyHeight,
        floorsFrom: 1,
        floorsTo: 5,
        storeyHeightM: 3.0,
        widthM: 2.4,
        depthM: 5.0,
        finishSides: 3,
        doorsM2: 0,
      );
      // perimeter 2.4 + 2×5 = 12.4; ×3 ×5 = 186
      expect(s.computeWallsM2(), closeTo(186.0, 0.01));
    });

    test('known walls m² wins', () {
      final s = StairwellParams(
        inputFocus: StairInputFocus.knownWallsM2,
        knownWallsM2: 50,
        floorsFrom: 1,
        floorsTo: 5,
      );
      expect(s.computeWallsM2(), 50);
    });

    test('total shaft height splits by storeys', () {
      final s = StairwellParams(
        inputFocus: StairInputFocus.totalHeightAndBox,
        floorsFrom: 1,
        floorsTo: 5,
        totalHeightM: 15,
        widthM: 2.4,
        depthM: 5.0,
        finishSides: 3,
      );
      expect(s.effectiveStoreyHeightM(), 3.0);
      expect(s.computeWallsM2(), closeTo(186.0, 0.01));
    });
  });

  test('schematic U-landing has walls, steps and elevation', () {
    final g = StairwellParams(
      plan: StairPlanKind.uLanding,
      widthM: 2.4,
      depthM: 5.0,
      storeyHeightM: 3.0,
      floorsFrom: 1,
      floorsTo: 5,
    ).buildSchematic();
    expect(g, isNotNull);
    expect(g!.walls.length, 4);
    expect(g.widthCm, 240);
    expect(g.depthCm, 500);
    expect(g.zones.any((z) => z.kind == 'landing'), isTrue);
    expect(g.zones.where((z) => z.kind == 'flight').length, 2);
    expect(g.stepsPerHalf, greaterThanOrEqualTo(3));
    expect(g.treads.length, greaterThan(g.stepsPerHalf));
    expect(g.landings.length, greaterThanOrEqualTo(2));
    expect(g.midLandingDepthCm, greaterThan(0));
    expect(g.bottomLandingDepthCm, greaterThan(0));
    expect(g.elevationLower.length, greaterThan(4));
    expect(g.elevationUpper.length, greaterThan(4));
    for (final p in [...g.elevationLower, ...g.elevationUpper]) {
      expect(p[0], inInclusiveRange(0.0, g.depthCm + 0.01));
      expect(p[1], inInclusiveRange(0.0, g.heightCm + 0.01));
    }
    expect(g.riserCm, inInclusiveRange(12.0, 20.0));
    expect(g.landingSlabCm, kStairLandingSlabCm);
  });

  test('openings deduct from wall area', () {
    final s = StairwellParams(
      inputFocus: StairInputFocus.boxAndStoreyHeight,
      widthM: 2.4,
      depthM: 5,
      storeyHeightM: 3,
      floorsFrom: 1,
      floorsTo: 1,
      openings: [
        StairwellOpening(kind: 'door', widthCm: 90, heightCm: 210),
      ],
    );
    final without = StairwellParams(
      inputFocus: StairInputFocus.boxAndStoreyHeight,
      widthM: 2.4,
      depthM: 5,
      storeyHeightM: 3,
      floorsFrom: 1,
      floorsTo: 1,
    ).computeWallsM2();
    expect(s.computeWallsM2(), closeTo(without - 90 * 210 / 10000, 0.05));
  });

  test('schematic null without box', () {
    expect(
      StairwellParams(widthM: 0, depthM: 5).buildSchematic(),
      isNull,
    );
  });

  test('SpecialSpace encode/parse roundtrip', () {
    final space = SpecialSpace(
      kind: SpecialSpaceKind.stairwell,
      wallsM2: 100,
      stair: StairwellParams(floorsFrom: 2, floorsTo: 4),
    );
    space.recomputeFromStair();
    final raw = space.encode();
    final back = SpecialSpace.tryParse(raw);
    expect(back, isNotNull);
    expect(back!.kind, SpecialSpaceKind.stairwell);
    expect(back.stair!.floorsFrom, 2);
    expect(back.stair!.floorsTo, 4);
  });
}
