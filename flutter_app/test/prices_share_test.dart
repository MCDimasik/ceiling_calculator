import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:ceiling_calculator/data/app_database.dart';
import 'package:ceiling_calculator/data/supplier_repository.dart';
import 'package:ceiling_calculator/domain/cost_calculator.dart';
import 'package:ceiling_calculator/domain/prices_share.dart';
import 'package:ceiling_calculator/domain/work_rates_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    initDatabaseFactory();
  });

  late Database db;
  late SupplierRepository suppliers;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openAppDatabase(inMemory: true);
    suppliers = SupplierRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('combined payload has work rates and suppliers', () async {
    final seed = seedWorkRatesCatalog();
    await WorkRatesCatalogStore.save(seed);

    final s = await suppliers.createSupplier('Сатурн');
    await suppliers.upsertPrice(
      s.id!,
      SupplierPrice(
        itemKey: 'armstrong_tile',
        productName: 'Плита Армстронг',
        unitPriceCost: 100,
        unitPriceClient: 150,
        supplierSku: 'SKU-1',
      ),
    );

    final payload = await PricesShare.buildPayload(
      suppliers: suppliers,
      fromOwner: 'director',
    );
    expect(payload['kind'], 'prices');
    expect(payload['stub'], isFalse);
    expect(payload['category_count'], seed.length);
    expect(payload['supplier_count'], 1);
    expect((payload['supplier_price_count'] as int) > 0, isTrue);
    final snap = payload['snapshot'] as Map;
    expect(snap['categories'], isA<List>());
    expect(snap['suppliers'], isA<List>());
  });

  test('suppliers-only apply merges by name without wiping work rates', () async {
    final seed = seedWorkRatesCatalog();
    await WorkRatesCatalogStore.save(seed);
    final originalPrice = seed.first.items.first.unitPrice;

    final src = await suppliers.createSupplier('Сатурн');
    await suppliers.upsertPrice(
      src.id!,
      SupplierPrice(
        itemKey: 'armstrong_tile',
        productName: 'Плита Армстронг',
        unitPriceCost: 100,
        unitPriceClient: 150,
        supplierSku: 'SKU-1',
      ),
    );

    final payload = await PricesShare.buildPayload(
      suppliers: suppliers,
      includeWorkRates: false,
    );
    expect(payload['category_count'], isNull);
    expect(payload['supplier_count'], 1);

    // Mutate work rates — must survive suppliers-only apply.
    final mutated = seedWorkRatesCatalog();
    mutated.first.items.first.unitPrice = 1;
    await WorkRatesCatalogStore.save(mutated);

    // Fresh DB side: delete supplier then re-apply into empty + merge name.
    await suppliers.deleteSupplier(src.id!);
    final note = await PricesShare.applyPayload(
      payload,
      suppliers: suppliers,
    );
    expect(note.contains('материалы'), isTrue);
    expect(WorkRatesCatalogStore.peek().first.items.first.unitPrice, 1);

    final list = await suppliers.listSuppliers();
    expect(list.map((s) => s.name), contains('Сатурн'));
    final re = list.firstWhere((s) => s.name == 'Сатурн');
    final prices = await suppliers.listPrices(re.id!);
    final purchase = prices.firstWhere((p) => p.itemKey == 'armstrong_tile');
    expect(purchase.unitPriceClient, 150);
    expect(purchase.supplierSku, 'SKU-1');

    // Restore work rates for isolation of next tests is unnecessary (tearDown).
    expect(originalPrice, isNot(1));
  });

  test('category share merges without wiping other categories', () async {
    final seed = seedWorkRatesCatalog();
    await WorkRatesCatalogStore.save(seed);
    final cat = seed.first;
    final item = cat.items.first;
    final originalOther = seed[1].items.first.unitPrice;

    final payload = await PricesShare.buildWorkCategoryPayload(
      category: cat,
      itemMatchKeys: [item.matchKey],
      fromOwner: 'foreman',
    );
    expect(payload['work_rates_mode'], 'merge');
    expect(payload['category_count'], 1);
    expect(payload['item_count'], 1);

    // Mutate shared item + another category; merge should restore shared only.
    final mutated = seedWorkRatesCatalog();
    mutated.first.items.first.unitPrice = 1;
    mutated[1].items.first.unitPrice = 2;
    await WorkRatesCatalogStore.save(mutated);

    final note = await PricesShare.applyPayload(
      payload,
      suppliers: suppliers,
    );
    expect(note.contains('слияние'), isTrue);
    final after = WorkRatesCatalogStore.peek();
    expect(after.first.items.first.unitPrice, item.unitPrice);
    expect(after[1].items.first.unitPrice, 2);
    expect(originalOther, isNot(2));
  });

  test('supplier item filter shares only selected keys', () async {
    final s = await suppliers.createSupplier('Бета');
    await suppliers.upsertPrice(
      s.id!,
      SupplierPrice(
        itemKey: 'armstrong_tile',
        productName: 'Плита',
        unitPriceClient: 10,
      ),
    );
    await suppliers.upsertPrice(
      s.id!,
      SupplierPrice(
        itemKey: 'guide_600',
        productName: 'Направляющая',
        unitPriceClient: 20,
      ),
    );

    final payload = await PricesShare.buildSupplierMaterialsPayload(
      suppliers: suppliers,
      supplierId: s.id!,
      itemKeys: ['guide_600'],
    );
    expect(payload['supplier_price_count'], 1);
    final snap = payload['snapshot'] as Map;
    final sups = snap['suppliers'] as List;
    final prices = (sups.first as Map)['prices'] as List;
    expect(prices.length, 1);
    expect((prices.first as Map)['item_key'], 'guide_600');
  });

  test('work+suppliers apply replaces work and merges materials', () async {
    final seed = seedWorkRatesCatalog();
    await WorkRatesCatalogStore.save(seed);

    final s = await suppliers.createSupplier('Альфа');
    await suppliers.upsertPrice(
      s.id!,
      SupplierPrice(
        itemKey: 'armstrong_tile',
        productName: 'Плита Армстронг',
        unitPriceCost: 10,
        unitPriceClient: 20,
      ),
    );

    final payload = await PricesShare.buildPayload(suppliers: suppliers);

    final mutated = seedWorkRatesCatalog();
    mutated.first.items.first.unitPrice = 99;
    await WorkRatesCatalogStore.save(mutated);

    await suppliers.upsertPrice(
      s.id!,
      SupplierPrice(
        itemKey: 'armstrong_tile',
        productName: 'Плита Армстронг',
        unitPriceCost: 1,
        unitPriceClient: 2,
      ),
    );

    final note = await PricesShare.applyPayload(
      payload,
      suppliers: suppliers,
    );
    expect(note.contains('работы'), isTrue);
    expect(note.contains('материалы'), isTrue);
    expect(
      WorkRatesCatalogStore.peek().first.items.first.unitPrice,
      seed.first.items.first.unitPrice,
    );
    final prices = await suppliers.listPrices(s.id!);
    expect(
      prices.firstWhere((p) => p.itemKey == 'armstrong_tile').unitPriceClient,
      20,
    );
  });
}
