import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../data/supplier_repository.dart';
import 'supplier_seed.dart';

/// Copies suppliers/prices from co-located Kivy DB if Flutter DB is empty.
Future<void> migrateLegacySuppliersIfNeeded(SupplierRepository suppliers) async {
  if ((await suppliers.listSuppliers()).isNotEmpty) return;

  final active = await defaultDatabasePath();
  final legacyCandidates = [
    p.join(p.dirname(active), 'ceiling_calculator.db'),
    p.join(Directory.current.path, 'ceiling_calculator.db'),
    p.join(Directory.current.path, '..', 'ceiling_calculator.db'),
  ];

  initDatabaseFactory();
  for (final legacy in legacyCandidates) {
    final normLegacy = p.normalize(legacy);
    if (!File(normLegacy).existsSync()) continue;
    if (normLegacy == p.normalize(active)) continue;

    final src = await openDatabase(normLegacy, readOnly: true);
    try {
      final srcCount = Sqflite.firstIntValue(
            await src.rawQuery('SELECT COUNT(*) FROM suppliers'),
          ) ??
          0;
      if (srcCount == 0) continue;

      final dst = await openAppDatabase();
      await dst.transaction((txn) async {
        for (final row in await src.query('suppliers')) {
          await txn.insert('suppliers', {
            'id': row['id'],
            'name': row['name'],
            'created_at': row['created_at'],
          });
        }
        final dstCols = (await txn.rawQuery('PRAGMA table_info(supplier_prices)'))
            .map((r) => r['name'] as String)
            .toSet();
        final srcCols = (await src.rawQuery('PRAGMA table_info(supplier_prices)'))
            .map((r) => r['name'] as String)
            .toSet();
        if (dstCols.contains('unit_price_cost') && srcCols.contains('unit_price_cost')) {
          for (final row in await src.query('supplier_prices')) {
            await txn.insert('supplier_prices', {
              'supplier_id': row['supplier_id'],
              'item_key': row['item_key'],
              'product_name': row['product_name'],
              'unit_price': row['unit_price'],
              'unit_price_cost': row['unit_price_cost'],
              'unit_price_client': row['unit_price_client'],
              'receipt_unit': row['receipt_unit'],
              'units_per_pack': row['units_per_pack'],
            });
          }
        }
      });
      return;
    } finally {
      await src.close();
    }
  }
}

Future<void> bootstrapSuppliers(SupplierRepository suppliers) async {
  await migrateLegacySuppliersIfNeeded(suppliers);
  try {
    await seedSaturnFallback(suppliers, merge: true);
  } catch (_) {}
}
