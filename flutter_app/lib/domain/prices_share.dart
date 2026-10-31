import '../data/supplier_repository.dart';
import 'work_rates_catalog.dart';

/// Combined «Расценки» sync: work catalog + supplier materials.
class PricesShare {
  PricesShare._();

  static Future<Map<String, dynamic>> buildPayload({
    SupplierRepository? suppliers,
    String? fromOwner,
    /// Full work catalog when true and [workCategories] is null.
    bool includeWorkRates = true,
    /// Explicit work subset (implies merge-on-accept unless [mergeWorkRates]
    /// is forced false — partial shares always merge).
    List<WorkRateCategory>? workCategories,
    bool mergeWorkRates = false,
    /// null → all suppliers; empty → none.
    Iterable<int>? supplierIds,
    /// Optional item filter per supplier id.
    Map<int, Iterable<String>>? supplierItemKeys,
  }) async {
    final out = <String, dynamic>{
      'stub': false,
      'kind': 'prices',
      'from_owner': fromOwner,
      'catalog_version': 3,
    };

    final snapshot = <String, dynamic>{};

    final List<WorkRateCategory>? cats;
    if (workCategories != null) {
      cats = workCategories;
    } else if (includeWorkRates) {
      cats = await WorkRatesCatalogStore.ensureLoaded();
    } else {
      cats = null;
    }

    if (cats != null && cats.isNotEmpty) {
      final itemCount =
          cats.fold<int>(0, (sum, c) => sum + c.items.length);
      final merge = mergeWorkRates || workCategories != null;
      out['category_count'] = cats.length;
      out['item_count'] = itemCount;
      out['work_rates_mode'] = merge ? 'merge' : 'replace';
      out['categories_preview'] = [
        for (final c in cats) {'name': c.name, 'items': c.items.length},
      ];
      snapshot['categories'] = [for (final c in cats) c.toJson()];
      snapshot['work_rates_mode'] = merge ? 'merge' : 'replace';
    }

    final skipSuppliers = suppliers == null ||
        (supplierIds != null &&
            supplierIds.isEmpty &&
            (supplierItemKeys == null || supplierItemKeys.isEmpty));

    if (!skipSuppliers) {
      final ids = supplierIds ??
          (supplierItemKeys != null && supplierItemKeys.isNotEmpty
              ? supplierItemKeys.keys
              : null);
      final parts = await suppliers.buildSuppliersShareParts(
        supplierIds: ids,
        itemKeysBySupplier: supplierItemKeys,
      );
      if (parts.snapshot.isNotEmpty) {
        out['supplier_count'] = parts.snapshot.length;
        out['supplier_price_count'] = parts.priceCount;
        out['suppliers_preview'] = parts.preview;
        snapshot['suppliers'] = parts.snapshot;
      }
    }

    if (snapshot.isEmpty) {
      throw StateError('Нечего отправлять: нет расценок и поставщиков');
    }
    out['snapshot'] = snapshot;
    return out;
  }

  /// One work category (optionally filtered items); merge on accept.
  static Future<Map<String, dynamic>> buildWorkCategoryPayload({
    required WorkRateCategory category,
    String? fromOwner,
    Iterable<String>? itemMatchKeys,
  }) {
    final keys = itemMatchKeys?.toSet();
    final items = keys == null
        ? category.items
        : [
            for (final i in category.items)
              if (keys.contains(i.matchKey)) i,
          ];
    if (items.isEmpty) {
      throw StateError('Нет позиций для отправки');
    }
    final slice = WorkRateCategory(
      id: category.id,
      name: category.name,
      items: [
        for (final i in items)
          WorkRateItem(
            matchKey: i.matchKey,
            name: i.name,
            unit: i.unit,
            unitPrice: i.unitPrice,
          ),
      ],
    );
    return buildPayload(
      fromOwner: fromOwner,
      includeWorkRates: false,
      workCategories: [slice],
      mergeWorkRates: true,
      supplierIds: const [],
    );
  }

  /// Materials for one supplier (optional item keys).
  static Future<Map<String, dynamic>> buildSupplierMaterialsPayload({
    required SupplierRepository suppliers,
    required int supplierId,
    String? fromOwner,
    Iterable<String>? itemKeys,
  }) {
    return buildPayload(
      suppliers: suppliers,
      fromOwner: fromOwner,
      includeWorkRates: false,
      supplierIds: [supplierId],
      supplierItemKeys:
          itemKeys == null ? null : {supplierId: itemKeys},
    );
  }

  /// Apply work rates (replace or merge) and/or suppliers (merge by name).
  static Future<String> applyPayload(
    Map<String, dynamic> payload, {
    required SupplierRepository suppliers,
  }) async {
    final snapshot = payload['snapshot'];
    if (snapshot is! Map) {
      throw StateError('В сообщении нет снимка расценок');
    }
    final notes = <String>[];

    final catsRaw = snapshot['categories'];
    if (catsRaw is List && catsRaw.isNotEmpty) {
      final mode = (snapshot['work_rates_mode'] as String?) ??
          (payload['work_rates_mode'] as String?) ??
          'replace';
      final int n;
      if (mode == 'merge') {
        n = await WorkRatesCatalogStore.mergeShareCategories(catsRaw);
        notes.add('работы: +$n поз. (слияние)');
      } else {
        n = await WorkRatesCatalogStore.applySharePayload({
          'snapshot': {'categories': catsRaw},
        });
        notes.add('работы: $n поз.');
      }
    }

    final supRaw = snapshot['suppliers'];
    if (supRaw is List && supRaw.isNotEmpty) {
      final n = await suppliers.applySuppliersShareSnapshot(supRaw);
      notes.add('материалы: $n строк');
    }

    if (notes.isEmpty) {
      throw StateError('Снимок пуст — нечего применять');
    }
    return notes.join(' · ');
  }

  static String titleForPayload(Map<String, dynamic> payload) {
    final hasWork = payload['category_count'] != null;
    final hasSup = payload['supplier_count'] != null;
    final mode = payload['work_rates_mode'] as String?;
    if (hasWork && hasSup) {
      return 'Расценки и материалы '
          '(${payload['category_count']} катег. · '
          '${payload['supplier_count']} пост.)';
    }
    if (hasSup) {
      final lines = (payload['supplier_price_count'] as num?)?.toInt();
      final n = payload['supplier_count'];
      final preview = payload['suppliers_preview'];
      String? supName;
      if (preview is List && preview.isNotEmpty && preview.first is Map) {
        supName = (preview.first as Map)['name'] as String?;
      }
      if (lines == 1 && supName != null) {
        return 'Материал · $supName';
      }
      if (n == 1 && supName != null) {
        return 'Поставщик «$supName»'
            '${lines != null ? ' ($lines стр.)' : ''}';
      }
      return 'Цены материалов ($n пост.'
          '${lines != null ? ', $lines стр.' : ''})';
    }
    if (hasWork && mode == 'merge') {
      final preview = payload['categories_preview'];
      if (preview is List && preview.length == 1 && preview.first is Map) {
        final name = (preview.first as Map)['name'] ?? 'категория';
        final items = (preview.first as Map)['items'] ?? payload['item_count'];
        if (items == 1) return 'Работа · $name';
        return 'Категория «$name» ($items поз.)';
      }
      return 'Работы (${payload['category_count']} катег., '
          '${payload['item_count']} поз.)';
    }
    return 'Расценки работ '
        '(${payload['category_count']} катег., '
        '${payload['item_count']} поз.)';
  }
}
