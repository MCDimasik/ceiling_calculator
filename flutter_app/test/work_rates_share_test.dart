import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ceiling_calculator/domain/work_rates_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('share payload round-trip replaces catalog', () async {
    final seed = seedWorkRatesCatalog();
    await WorkRatesCatalogStore.save(seed);

    final payload = await WorkRatesCatalogStore.buildSharePayload(
      fromOwner: 'director',
    );
    expect(payload['stub'], isFalse);
    expect(payload['kind'], 'prices');
    expect(payload['category_count'], seed.length);
    expect((payload['item_count'] as int) > 0, isTrue);
    expect(payload['snapshot'], isA<Map>());

    // Mutate local catalog, then apply share → restore seed prices.
    final mutated = seedWorkRatesCatalog();
    mutated.first.items.first.unitPrice = 1;
    await WorkRatesCatalogStore.save(mutated);
    expect(
      WorkRatesCatalogStore.peek().first.items.first.unitPrice,
      1,
    );

    final n = await WorkRatesCatalogStore.applySharePayload(payload);
    expect(n, payload['item_count']);
    expect(
      WorkRatesCatalogStore.peek().first.items.first.unitPrice,
      seed.first.items.first.unitPrice,
    );
  });

  test('applySharePayload rejects empty snapshot', () async {
    expect(
      () => WorkRatesCatalogStore.applySharePayload({'kind': 'prices'}),
      throwsStateError,
    );
  });
}
