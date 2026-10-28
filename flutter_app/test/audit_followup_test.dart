import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/as_built_export.dart';
import 'package:ceiling_calculator/domain/cost_calculator.dart';
import 'package:ceiling_calculator/domain/finish_design_baseline.dart';
import 'package:ceiling_calculator/domain/finish_model.dart';
import 'package:ceiling_calculator/domain/layout_design_baseline.dart';
import 'package:ceiling_calculator/domain/layout_layers.dart';
import 'package:ceiling_calculator/domain/models.dart';
import 'package:ceiling_calculator/domain/project_price_resolver.dart';
import 'package:ceiling_calculator/domain/typical_floor_diff.dart';

void main() {
  test('ViewTransform roundtrip preserves scale and translation', () {
    final vt = const ViewTransform(scale: 2.5, tx: 120, ty: -40);
    final parsed = ViewTransform.tryParse(Map<String, dynamic>.from(vt.toJson()));
    expect(parsed, isNotNull);
    expect(parsed!.scale, 2.5);
    expect(parsed.tx, 120);
    expect(parsed.ty, -40);
    final m = parsed.toMatrix();
    final back = ViewTransform.fromMatrix(m);
    expect(back.scale, closeTo(2.5, 0.001));
    expect(back.tx, closeTo(120, 0.001));
    expect(back.ty, closeTo(-40, 0.001));
  });

  test('saved ViewTransform is preferred over fit unless force-fit clears it', () {
    final saved = const ViewTransform(scale: 3, tx: 50, ty: 60);
    final json = Map<String, dynamic>.from(saved.toJson());
    final restored = ViewTransform.tryParse(json)!;
    expect(restored.scale, 3);
    // Force-fit path overwrites json with a new transform:
    final fit = const ViewTransform(scale: 1.2, tx: 10, ty: 20);
    json.addAll(fit.toJson());
    expect(ViewTransform.tryParse(json)!.scale, 1.2);
  });

  test('ensureFinishDesignBaseline keeps project-vs-fact deltas', () {
    final room = Room(
      name: 'R',
      walls: [
        [0.0, 0.0, 400.0, 0.0],
        [400.0, 0.0, 400.0, 300.0],
        [400.0, 300.0, 0.0, 300.0],
        [0.0, 300.0, 0.0, 0.0],
      ],
      gridOffsetX: 10,
      gridOffsetY: 20,
    );
    ensureFinishDesignBaseline(room);
    expect(hasFinishDesignBaseline(room), isTrue);
    room.gridOffsetX = 40;
    room.gridOffsetY = 50;
    // Layout persist path: ensure again must NOT wipe baseline.
    ensureFinishDesignBaseline(room);
    final (dx, dy) = gridOffsetDelta(room);
    expect(dx, 30);
    expect(dy, 30);

    rebaselineFinishDesign(room);
    final (dx2, dy2) = gridOffsetDelta(room);
    expect(dx2, 0);
    expect(dy2, 0);
  });

  test('fromLayoutLayers maps wallDims and tileDims', () {
    const layers = LayoutLayerVisibility(
      guides: false,
      lights: false,
      notes: true,
      wallDims: false,
      tileDims: true,
    );
    final opts = AsBuiltExportOptions.fromLayoutLayers(layers);
    expect(opts.showGuides, isFalse);
    expect(opts.showLights, isFalse);
    expect(opts.showNotes, isTrue);
    expect(opts.showWallDims, isFalse);
    expect(opts.showTileDims, isTrue);
  });

  test('resolveFinishSupplierPrice fuzzy matches catalog keys', () {
    final prices = {
      'Плиты/кассеты (Армстронг)': SupplierPrice(
        itemKey: 'armstrong_tile',
        productName: 'Плита Армстронг',
        unitPriceClient: 100,
        supplierSku: 'ARM-1',
      ),
      'Краска стены': SupplierPrice(
        itemKey: 'paint',
        productName: 'Краска для стен',
        unitPriceClient: 50,
        supplierSku: 'WALL-SKU',
      ),
      'Ламинат пол 33': SupplierPrice(
        itemKey: 'lam',
        productName: 'Ламинат пол',
        unitPriceClient: 80,
        supplierSku: 'FLOOR-SKU',
      ),
    };
    expect(resolveFinishSku(sectionKey: 'finish_ceiling', prices: prices), 'ARM-1');
    expect(resolveFinishSku(sectionKey: 'finish_wall', prices: prices), 'WALL-SKU');
    expect(resolveFinishSku(sectionKey: 'finish_floor', prices: prices), 'FLOOR-SKU');
  });

  test('resolveFinishSupplierPrice prefers direct finish_* key', () {
    final prices = {
      'finish_floor': SupplierPrice(
        itemKey: 'ff',
        productName: 'Отделка пол',
        unitPriceClient: 10,
        supplierSku: 'DIRECT',
      ),
      'Ламинат пол': SupplierPrice(
        itemKey: 'lam',
        productName: 'Ламинат',
        unitPriceClient: 20,
        supplierSku: 'FUZZY',
      ),
    };
    expect(resolveFinishSku(sectionKey: 'finish_floor', prices: prices), 'DIRECT');
  });

  test('formatTypicalFloorGeometryDiff reports deltas', () {
    final template = Room(
      id: 1,
      name: '101',
      walls: [
        [0.0, 0.0, 400.0, 0.0],
        [400.0, 0.0, 400.0, 300.0],
        [400.0, 300.0, 0.0, 300.0],
        [0.0, 300.0, 0.0, 0.0],
      ],
      lightFixtures: [
        [1, 1],
      ],
    );
    final copy = Room(
      id: 2,
      name: '101 1',
      walls: [
        [0.0, 0.0, 500.0, 0.0],
        [500.0, 0.0, 500.0, 300.0],
        [500.0, 300.0, 0.0, 300.0],
        [0.0, 300.0, 0.0, 0.0],
      ],
      lightFixtures: [
        [1, 1],
        [2, 2],
      ],
    );
    final text = formatTypicalFloorGeometryDiff(template: template, copies: [copy]);
    expect(text, contains('101 1'));
    expect(text, contains('свет Δ1'));
    expect(text, contains('S Δ'));
  });
}
