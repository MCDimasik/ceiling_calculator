import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/ceiling_grid.dart';
import 'package:ceiling_calculator/domain/layout_layers.dart';
import 'package:ceiling_calculator/domain/models.dart';
import 'package:ceiling_calculator/domain/project_materials.dart';
import 'package:ceiling_calculator/ui/widgets/layout_canvas_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('layout canvas matches golden for rectangle room', (tester) async {
    const size = Size(400, 320);
    final walls = [
      [0.0, 0.0, 600.0, 0.0],
      [600.0, 0.0, 600.0, 400.0],
      [600.0, 400.0, 0.0, 400.0],
      [0.0, 400.0, 0.0, 0.0],
    ];
    final grid = CeilingGrid();
    grid.rebuild(
      roomPoints: pointsFromWalls(walls),
      walls: walls,
      lightIds: const {},
    );
    final metrics = LayoutMetrics.compute(size, walls);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: RepaintBoundary(
                key: const Key('layout_canvas'),
                child: CustomPaint(
                  painter: LayoutPainter(
                    walls: walls,
                    grid: grid,
                    metrics: metrics,
                    showTileDims: false,
                    showWallDims: false,
                    visualOffsetX: 0,
                    visualOffsetY: 0,
                    visibleWorld: const Rect.fromLTRB(-100, -100, 700, 500),
                    lightIds: const {},
                    guides: const {},
                    wallsForGuides: walls,
                    showGuides: false,
                    layers: const LayoutLayerVisibility(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('layout_canvas')),
      matchesGoldenFile('goldens/layout_rect_room.png'),
    );
  });
}
