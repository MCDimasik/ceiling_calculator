import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/design_walls_baseline.dart';
import 'package:ceiling_calculator/domain/finish_capture_impact.dart';
import 'package:ceiling_calculator/domain/finish_design_baseline.dart';
import 'package:ceiling_calculator/domain/layout_design_baseline.dart';
import 'package:ceiling_calculator/domain/geometry_polygon.dart';
import 'package:ceiling_calculator/domain/models.dart';
import 'package:ceiling_calculator/domain/photo_plan.dart';
import 'package:ceiling_calculator/domain/room_scan_import.dart';
import 'package:ceiling_calculator/domain/finish_model.dart';
import 'package:ceiling_calculator/domain/wall_as_built_export.dart';
import 'package:ceiling_calculator/domain/wall_elevation_geometry.dart';
import 'package:ceiling_calculator/domain/wall_geometry.dart';
import 'package:ceiling_calculator/domain/wall_polygon_diff.dart';

void main() {
  group('geometry_polygon', () {
    test('footprintFromWalls rectangle 4x3 m', () {
      final walls = [
        [0.0, 0.0, 400.0, 0.0],
        [400.0, 0.0, 400.0, 300.0],
        [400.0, 300.0, 0.0, 300.0],
        [0.0, 300.0, 0.0, 0.0],
      ];
      final fp = footprintFromWalls(walls);
      expect(fp.areaM2, closeTo(12, 0.01));
      expect(fp.perimeterM, closeTo(14, 0.01));
    });

    test('validatePhotoPlanPoints rejects self-intersection', () {
      final pts = [
        const Offset(0, 0),
        const Offset(100, 100),
        const Offset(100, 0),
        const Offset(0, 100),
      ];
      expect(validatePhotoPlanPoints(pts), isNotNull);
    });
  });

  group('photo_plan wallsFromPhotoPlan', () {
    test('scales square by known wall', () {
      final walls = wallsFromPhotoPlan(
        imagePoints: const [
          Offset(0, 0),
          Offset(100, 0),
          Offset(100, 100),
          Offset(0, 100),
        ],
        wallIndex: 0,
        wallLengthCm: 500,
      );
      expect(walls.length, 4);
      expect(footprintFromWalls(walls).areaM2, closeTo(25, 0.1));
    });
  });

  group('wall_polygon_diff', () {
    test('detects area delta between design and fact', () {
      final design = [
        [0.0, 0.0, 400.0, 0.0],
        [400.0, 0.0, 400.0, 300.0],
        [400.0, 300.0, 0.0, 300.0],
        [0.0, 300.0, 0.0, 0.0],
      ];
      final fact = [
        [0.0, 0.0, 420.0, 0.0],
        [420.0, 0.0, 420.0, 300.0],
        [420.0, 300.0, 0.0, 300.0],
        [0.0, 300.0, 0.0, 0.0],
      ];
      final diff = compareWallPolygons(design, fact);
      expect(diff.hasDesignBaseline, isTrue);
      expect(diff.areaDeltaM2, closeTo(0.6, 0.1));
      expect(diff.hasSignificantDiff, isTrue);
    });

    test('no baseline when design missing', () {
      final fact = [
        [0.0, 0.0, 100.0, 0.0],
        [100.0, 0.0, 100.0, 100.0],
        [100.0, 100.0, 0.0, 100.0],
        [0.0, 100.0, 0.0, 0.0],
      ];
      final diff = compareWallPolygons(null, fact);
      expect(diff.hasDesignBaseline, isFalse);
    });
  });

  group('finish_design_baseline', () {
    test('snapshots floor grid and height', () {
      final room = Room(
        name: 'R',
        walls: [
          [0, 0, 400, 0],
          [400, 0, 400, 300],
          [400, 300, 0, 300],
          [0, 300, 0, 0],
        ],
        floorGridOffsetX: 12,
        floorGridOffsetY: 8,
        ceilingHeightCm: 280,
      );
      ensureFinishDesignBaseline(room);
      expect(readFloorDesignBaseline(room).offsetX, 12);
      expect(readDesignCeilingHeightCm(room), 280);
      expect(readFloorDesignRotation(room), 0);
    });

    test('rotation delta after fact change', () {
      final room = Room(
        name: 'R',
        walls: [
          [0, 0, 400, 0],
          [400, 0, 400, 300],
          [400, 300, 0, 300],
          [0, 300, 0, 0],
        ],
        floorLayoutRotationDeg: 0,
      );
      ensureFinishDesignBaseline(room);
      room.floorLayoutRotationDeg = 90;
      expect(floorLayoutRotationDelta(room), 90);
      expect(formatFloorGridDeltaLabel(room), contains('90°'));
    });

    test('rebaseline replaces design walls after fact change', () {
      final room = Room(
        name: 'R',
        walls: [
          [0, 0, 400, 0],
          [400, 0, 400, 300],
          [400, 300, 0, 300],
          [0, 300, 0, 0],
        ],
        gridOffsetX: 5,
        floorGridOffsetX: 12,
        ceilingHeightCm: 280,
      );
      ensureFinishDesignBaseline(room);
      room.walls = [
        [0, 0, 500, 0],
        [500, 0, 500, 300],
        [500, 300, 0, 300],
        [0, 300, 0, 0],
      ];
      room.gridOffsetX = 20;
      room.floorGridOffsetX = 30;
      room.ceilingHeightCm = 300;
      rebaselineFinishDesign(room);
      expect(readDesignWalls(room)![0][2], 500);
      expect(readDesignBaseline(room).offsetX, 20);
      expect(readFloorDesignBaseline(room).offsetX, 30);
      expect(readDesignCeilingHeightCm(room), 300);
    });
  });

  group('finish_capture_impact', () {
    test('detects floor and walls delta', () {
      final room = Room(
        name: 'R',
        walls: [
          [0, 0, 400, 0],
          [400, 0, 400, 300],
          [400, 300, 0, 300],
          [0, 300, 0, 0],
        ],
        ceilingHeightCm: 270,
      );
      final newWalls = [
        [0.0, 0.0, 500.0, 0.0],
        [500.0, 0.0, 500.0, 300.0],
        [500.0, 300.0, 0.0, 300.0],
        [0.0, 300.0, 0.0, 0.0],
      ];
      final impact = computeFinishCaptureImpact(room: room, newWalls: newWalls);
      expect(impact.floorDeltaM2, closeTo(3, 0.2));
      expect(impact.wallsNetDeltaM2, greaterThan(0));
    });
  });

  group('design_walls_baseline', () {
    test('write-once snapshot in layoutViewJson', () {
      final room = Room(name: 'R', walls: [
        [0, 0, 400, 0],
        [400, 0, 400, 300],
        [400, 300, 0, 300],
        [0, 300, 0, 0],
      ]);
      ensureDesignWallsBaseline(room);
      expect(readDesignWalls(room)?.length, 4);
      room.walls = [
        [0, 0, 500, 0],
        [500, 0, 500, 300],
        [500, 300, 0, 300],
        [0, 300, 0, 0],
      ];
      ensureDesignWallsBaseline(room);
      expect(readDesignWalls(room)![0][2], 400);
    });
  });

  group('ar import', () {
    test('importFromArCorners builds normalized walls', () {
      final result = importFromArCorners([
        (0.0, 0.0),
        (4.0, 0.0),
        (4.0, 3.0),
        (0.0, 3.0),
      ]);
      expect(result.walls.length, 4);
      expect(result.footprint.areaM2, closeTo(12, 0.1));
    });
  });

  group('wall_geometry', () {
    test('nearestWallHit finds wall segment', () {
      final walls = [
        [0.0, 0.0, 400.0, 0.0],
        [400.0, 0.0, 400.0, 300.0],
      ];
      final hit = nearestWallHit(walls, 200, 5);
      expect(hit?.wallIndex, 0);
      expect(hit!.offsetAlongCm, closeTo(200, 1));
    });
  });

  group('wall_elevation_geometry', () {
    test('openingRectsOnWall respects wall index and gap', () {
      final openings = [
        RoomOpening(
          kind: 'window',
          widthCm: 120,
          heightCm: 140,
          wallIndex: 1,
          offsetAlongWallCm: 50,
          sillHeightCm: 90,
          quantity: 2,
        ),
      ];
      final rects = openingRectsOnWall(
        wallIndex: 1,
        wallLengthCm: 400,
        roomHeightCm: 280,
        openings: openings,
      );
      expect(rects.length, 2);
      expect(rects.first.leftCm, 50);
      expect(rects.last.leftCm, closeTo(50 + 120 + openingGapAlongWallCm, 0.1));
    });
  });

  group('wall_as_built_export', () {
    test('renderWallElevationCadPng returns bytes for room with walls', () async {
      final room = Room(
        name: 'R',
        walls: [
          [0, 0, 400, 0],
          [400, 0, 400, 300],
          [400, 300, 0, 300],
          [0, 300, 0, 0],
        ],
        ceilingHeightCm: 270,
        wallFinishLayers: [
          FinishLayer(
            kind: FinishLayerKind.tile,
            tileWidthCm: 60,
            tileHeightCm: 60,
          ).toJson(),
        ],
        openings: [
          RoomOpening(
            kind: 'door',
            widthCm: 90,
            heightCm: 210,
            wallIndex: 0,
            offsetAlongWallCm: 100,
          ).toJson(),
        ],
      );
      final bytes = await renderWallElevationCadPng(room, pageSize: const Size(800, 600));
      expect(bytes.length, greaterThan(100));
    });
  });
}
