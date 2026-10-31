import 'package:sqflite/sqflite.dart';

import '../domain/cost_calculator.dart';
import '../domain/material_catalog.dart';
import '../domain/sync_revisions.dart';
import '../domain/user_product_aliases.dart';

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
    await SyncRevisions.touch(SyncRevisions.supplierKey(s.name));
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
    final hidden = await loadHiddenItemKeys(supplierId);
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
              supplierSku: r['supplier_sku'] as String? ?? '',
            ))
        .where((p) => !hidden.contains(p.itemKey))
        .toList();
  }

  /// Keep [keeper], absorb prices from [absorb], hide absorbed keys, bind aliases.
  Future<SupplierPrice> mergePrices({
    required int supplierId,
    required String keeperItemKey,
    required List<String> absorbItemKeys,
    required String displayName,
    required Iterable<String> aliasLabels,
  }) async {
    final all = await listPrices(supplierId);
    // listPrices hides already-hidden; load raw for merge sources.
    final rows = await _db.query(
      'supplier_prices',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
    );
    SupplierPrice? keeper;
    final absorb = <SupplierPrice>[];
    for (final r in rows) {
      final p = SupplierPrice(
        itemKey: r['item_key'] as String,
        productName: r['product_name'] as String,
        unitPriceCost: (r['unit_price_cost'] as num?)?.toDouble() ?? 0,
        unitPriceClient: (r['unit_price_client'] as num?)?.toDouble() ?? 0,
        receiptUnit: r['receipt_unit'] as String? ?? 'piece',
        unitsPerPack: (r['units_per_pack'] as num?)?.toDouble() ?? 1,
        supplierSku: r['supplier_sku'] as String? ?? '',
      );
      if (p.itemKey == keeperItemKey) keeper = p;
      if (absorbItemKeys.contains(p.itemKey)) absorb.add(p);
    }
    if (keeper == null) {
      for (final p in all) {
        if (p.itemKey == keeperItemKey) {
          keeper = p;
          break;
        }
      }
    }
    if (keeper == null) {
      throw StateError('Не найдена позиция $keeperItemKey');
    }

    var cost = keeper.unitPriceCost;
    var client = keeper.unitPriceClient;
    var upp = keeper.unitsPerPack;
    var sku = keeper.supplierSku;
    var receiptUnit = keeper.receiptUnit;
    for (final p in absorb) {
      if (p.itemKey == keeperItemKey) continue;
      if (cost <= 0 && p.unitPriceCost > 0) cost = p.unitPriceCost;
      if (client <= 0 && p.unitPriceClient > 0) client = p.unitPriceClient;
      if (upp <= 1 && p.unitsPerPack > 1) upp = p.unitsPerPack;
      if (sku.isEmpty && p.supplierSku.isNotEmpty) sku = p.supplierSku;
      if (receiptUnit == 'piece' && p.receiptUnit == 'pack') {
        receiptUnit = p.receiptUnit;
      }
    }

    final merged = SupplierPrice(
      itemKey: keeperItemKey,
      productName: displayName.trim().isEmpty ? keeper.productName : displayName.trim(),
      unitPriceCost: cost,
      unitPriceClient: client,
      receiptUnit: receiptUnit,
      unitsPerPack: upp,
      supplierSku: sku,
    );
    await upsertPrice(supplierId, merged);

    final labels = <String>{
      ...aliasLabels,
      merged.productName,
      for (final p in absorb) p.productName,
      for (final p in absorb) p.itemKey,
    };
    final aliases = await UserProductAliasStore.load();
    await aliases.bindLabels(labels, keeperItemKey);

    final toHide = absorbItemKeys.where((k) => k != keeperItemKey).toList();
    for (final k in toHide) {
      await deletePrice(supplierId, k);
    }
    await hideItemKeys(supplierId, toHide);
    return merged;
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
        'supplier_sku': price.supplierSku,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final rows = await _db.query(
      'suppliers',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [supplierId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      await SyncRevisions.touch(
        SyncRevisions.supplierKey(rows.first['name'] as String),
      );
    }
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

  Map<String, dynamic> _priceToSyncJson(SupplierPrice p) => {
        'item_key': p.itemKey,
        'product_name': p.productName,
        'unit_price_cost': p.unitPriceCost,
        'unit_price_client': p.unitPriceClient,
        'receipt_unit': p.receiptUnit,
        'units_per_pack': p.unitsPerPack,
        'supplier_sku': p.supplierSku,
      };

  SupplierPrice _priceFromSyncJson(Map<String, dynamic> j) => SupplierPrice(
        itemKey: j['item_key'] as String? ?? '',
        productName: j['product_name'] as String? ?? '',
        unitPriceCost: (j['unit_price_cost'] as num?)?.toDouble() ?? 0,
        unitPriceClient: (j['unit_price_client'] as num?)?.toDouble() ?? 0,
        receiptUnit: j['receipt_unit'] as String? ?? 'piece',
        unitsPerPack: (j['units_per_pack'] as num?)?.toDouble() ?? 1,
        supplierSku: j['supplier_sku'] as String? ?? '',
      );

  /// Snapshot of one or all suppliers for inbox «Расценки / материалы».
  ///
  /// [supplierIds] null → all; empty → none.
  /// [itemKeysBySupplier] optional filter per supplier (explicit selection).
  Future<({List<Map<String, dynamic>> preview, List<Map<String, dynamic>> snapshot, int priceCount})>
      buildSuppliersShareParts({
    Iterable<int>? supplierIds,
    Map<int, Iterable<String>>? itemKeysBySupplier,
  }) async {
    final all = await listSuppliers();
    final filter = supplierIds?.toSet();
    final chosen = filter == null
        ? all
        : [for (final s in all) if (s.id != null && filter.contains(s.id)) s];
    final preview = <Map<String, dynamic>>[];
    final snap = <Map<String, dynamic>>[];
    var priceCount = 0;
    for (final s in chosen) {
      if (s.id == null) continue;
      final prices = await listPrices(s.id!);
      final keyFilter = itemKeysBySupplier?[s.id!]?.toSet();
      final List<SupplierPrice> lines;
      if (keyFilter != null) {
        lines = [
          for (final p in prices)
            if (keyFilter.contains(p.itemKey)) p,
        ];
      } else {
        // Skip empty default catalogs with all zeros when sending whole supplier.
        final priced = [
          for (final p in prices)
            if (p.unitPriceCost > 0 ||
                p.unitPriceClient > 0 ||
                p.supplierSku.isNotEmpty)
              p,
        ];
        lines = priced.isNotEmpty ? priced : prices;
      }
      if (lines.isEmpty) continue;
      priceCount += lines.length;
      preview.add({'name': s.name, 'prices': lines.length});
      snap.add({
        'name': s.name,
        'prices': [for (final p in lines) _priceToSyncJson(p)],
      });
    }
    return (preview: preview, snapshot: snap, priceCount: priceCount);
  }

  /// Merge suppliers from share snapshot by name (create if missing).
  /// Returns number of price rows upserted.
  Future<int> applySuppliersShareSnapshot(List<dynamic> suppliersRaw) async {
    var applied = 0;
    for (final raw in suppliersRaw) {
      if (raw is! Map) continue;
      final name = (raw['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final supplier = await getOrCreateSupplier(name);
      final pricesRaw = raw['prices'];
      if (pricesRaw is! List) continue;
      for (final pr in pricesRaw) {
        if (pr is! Map) continue;
        final price = _priceFromSyncJson(Map<String, dynamic>.from(pr));
        if (price.itemKey.isEmpty && price.productName.isEmpty) continue;
        if (price.itemKey.isEmpty) {
          // Fallback key from name — rare for custom lines.
          final key =
              'sync_${price.productName.hashCode.toRadixString(16)}';
          await upsertPrice(
            supplier.id!,
            SupplierPrice(
              itemKey: key,
              productName: price.productName,
              unitPriceCost: price.unitPriceCost,
              unitPriceClient: price.unitPriceClient,
              receiptUnit: price.receiptUnit,
              unitsPerPack: price.unitsPerPack,
              supplierSku: price.supplierSku,
            ),
          );
        } else {
          await upsertPrice(supplier.id!, price);
        }
        applied++;
      }
    }
    return applied;
  }
}
