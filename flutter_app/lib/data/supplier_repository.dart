import 'package:sqflite/sqflite.dart';

import '../domain/cost_calculator.dart';
import '../domain/material_catalog.dart';

class SupplierRepository {
  SupplierRepository(this._db);

  final Database _db;

  Future<List<Supplier>> listSuppliers() async {
    final rows = await _db.query('suppliers', orderBy: 'name ASC');
    return rows
        .map((r) => Supplier(
              id: r['id'] as int,
              name: r['name'] as String,
              createdAt: DateTime.parse(r['created_at'] as String),
            ))
        .toList();
  }

  Future<Supplier> createSupplier(String name) async {
    final s = Supplier(name: name.trim());
    s.id = await _db.insert('suppliers', {
      'name': s.name,
      'created_at': s.createdAt.toIso8601String(),
    });
    await _ensureDefaultPrices(s.id!);
    return s;
  }

  Future<Supplier> getOrCreateSupplier(String name) async {
    final trimmed = name.trim();
    final rows = await _db.query(
      'suppliers',
      where: 'LOWER(name) = LOWER(?)',
      whereArgs: [trimmed],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return Supplier(
        id: rows.first['id'] as int,
        name: rows.first['name'] as String,
        createdAt: DateTime.parse(rows.first['created_at'] as String),
      );
    }
    return createSupplier(trimmed);
  }

  Future<void> renameSupplier(int id, String name) async {
    await _db.update('suppliers', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteSupplier(int id) async {
    await _db.delete('supplier_prices', where: 'supplier_id = ?', whereArgs: [id]);
    await _db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<SupplierPrice>> listPrices(int supplierId) async {
    await _ensureDefaultPrices(supplierId);
    final rows = await _db.query(
      'supplier_prices',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'product_name ASC',
    );
    return rows
        .map((r) => SupplierPrice(
              itemKey: r['item_key'] as String,
              productName: r['product_name'] as String,
              unitPriceCost: (r['unit_price_cost'] as num?)?.toDouble() ?? 0,
              unitPriceClient: (r['unit_price_client'] as num?)?.toDouble() ?? 0,
              receiptUnit: r['receipt_unit'] as String? ?? 'piece',
              unitsPerPack: (r['units_per_pack'] as num?)?.toDouble() ?? 1,
            ))
        .toList();
  }

  Future<void> upsertPrice(int supplierId, SupplierPrice price) async {
    await _db.insert(
      'supplier_prices',
      {
        'supplier_id': supplierId,
        'item_key': price.itemKey,
        'product_name': price.productName,
        'unit_price': price.unitPriceClient,
        'unit_price_cost': price.unitPriceCost,
        'unit_price_client': price.unitPriceClient,
        'receipt_unit': price.receiptUnit,
        'units_per_pack': price.unitsPerPack,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, SupplierPrice>> pricesByCalcMatchKey(int supplierId) async {
    final prices = await listPrices(supplierId);
    final map = <String, SupplierPrice>{};
    for (final p in prices) {
      map.putIfAbsent(p.calcMatchKey, () => p);
    }
    return map;
  }

  Future<void> deletePrice(int supplierId, String itemKey) async {
    await _db.delete(
      'supplier_prices',
      where: 'supplier_id = ? AND item_key = ?',
      whereArgs: [supplierId, itemKey],
    );
  }

  Future<void> _ensureDefaultPrices(int supplierId) async {
    for (final e in catalogEntries) {
      final existing = await _db.query(
        'supplier_prices',
        where: 'supplier_id = ? AND item_key = ?',
        whereArgs: [supplierId, e.itemKey],
        limit: 1,
      );
      if (existing.isNotEmpty) continue;
      await _db.insert('supplier_prices', {
        'supplier_id': supplierId,
        'item_key': e.itemKey,
        'product_name': e.displayName,
        'unit_price': 0,
        'unit_price_cost': 0,
        'unit_price_client': 0,
        'receipt_unit': 'piece',
        'units_per_pack': defaultUnitsPerPack(e.itemKey).toDouble(),
      });
    }
  }
}
