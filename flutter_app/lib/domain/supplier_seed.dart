import '../data/supplier_repository.dart';
import 'cost_calculator.dart';
import 'material_catalog.dart';

const saturnFallbackCost = <String, (String, double)>{
  'armstrong_retail': ('Плита Армстронг Retail (Сат-147189)', 190.0),
  'guide_3600': ('Направляющая 3600', 131.0),
  'guide_1200': ('Направляющая 1200', 44.0),
  'guide_600': ('Направляющая 600', 22.68),
  'corner': ('Уголок 3 м', 89.0),
  'susp_05': ('Подвес 0,5 м', 11.0),
  'light_fixture_led': ('Светильник LED 600×600', 656.0),
};

Future<Supplier> seedSaturnFallback(SupplierRepository repo, {bool merge = true}) async {
  final s = await repo.getOrCreateSupplier('Сатурн');
  final existing = await repo.listPrices(s.id!);
  final byKey = {for (final p in existing) p.itemKey: p};
  for (final e in saturnFallbackCost.entries) {
    final cur = byKey[e.key];
    if (merge && cur != null && cur.unitPriceCost > 0) continue;
    final cost = e.value.$2;
    final client = double.parse((cost * 1.1).toStringAsFixed(2));
    await repo.upsertPrice(
      s.id!,
      SupplierPrice(
        itemKey: e.key,
        productName: e.value.$1,
        unitPriceCost: cost,
        unitPriceClient: client,
        receiptUnit: 'piece',
        unitsPerPack: defaultUnitsPerPack(e.key).toDouble(),
      ),
    );
  }
  return s;
}
