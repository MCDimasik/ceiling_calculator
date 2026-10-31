import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ceiling_calculator/domain/finish_material_links.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('kit share payload round-trip creates local copy', () async {
    final kit = FinishMountKit(
      id: 'kit_src',
      name: 'Краска стандарт',
      section: 'walls',
      layerKind: 'paint',
      items: [
        FinishMaterialLink(
          itemKey: 'paint_a',
          productName: 'Краска А',
          qtyPerUnit: 0.2,
          unit: 'л',
        ),
      ],
    );
    await upsertMountKit(kit);

    final payload = buildMountKitSharePayload(kit, fromOwner: 'director');
    expect(payload['stub'], isFalse);
    expect(payload['kind'], 'kit');
    expect(payload['item_count'], 1);
    expect(payload['snapshot'], isA<Map>());

    await saveMountKits([]);
    expect(await loadMountKits(), isEmpty);

    final saved = await applyMountKitSharePayload(payload);
    expect(saved.name, 'Краска стандарт');
    expect(saved.id, isNot(equals('kit_src')));
    expect(saved.items.length, 1);
    expect(saved.items.first.productName, 'Краска А');

    final list = await loadMountKits();
    expect(list.length, 1);
    expect(list.first.id, saved.id);
  });

  test('applyMountKitSharePayload rejects empty snapshot', () async {
    expect(
      () => applyMountKitSharePayload({'kind': 'kit'}),
      throwsStateError,
    );
  });
}
