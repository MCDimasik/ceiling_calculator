import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import '../data/supplier_repository.dart';
import 'cost_calculator.dart';
import 'material_catalog.dart';
import 'product_aliases.dart';
import 'receipt_templates.dart';

class ParsedReceiptItem {
  ParsedReceiptItem({
    required this.rawName,
    required this.unitPrice,
    this.itemKey,
    this.receiptUnit,
    this.unitsPerPack,
    this.unitPriceReceipt,
  });

  final String rawName;
  final double unitPrice;
  final String? itemKey;
  final String? receiptUnit;
  final double? unitsPerPack;
  final double? unitPriceReceipt;
}

class ParsedReceipt {
  ParsedReceipt({required this.supplierName, required this.items});
  final String supplierName;
  final List<ParsedReceiptItem> items;
}

class ReceiptApplyResult {
  ReceiptApplyResult({
    required this.supplierId,
    required this.supplierName,
    required this.matched,
    required this.unmatched,
  });
  final int supplierId;
  final String supplierName;
  final List<Map<String, dynamic>> matched;
  final List<ParsedReceiptItem> unmatched;
}

double? _parsePriceToken(String s) {
  final cleaned = s.replaceAll(' ', '').replaceAll(',', '.');
  final m = RegExp(r'(\d+(?:\.\d{1,2})?)').firstMatch(cleaned);
  if (m == null) return null;
  return double.tryParse(m.group(1)!);
}

ParsedReceipt parseReceiptText(String text) {
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final supplierName = lines.isNotEmpty ? lines.first : 'Поставщик';
  final items = <ParsedReceiptItem>[];
  for (final ln in lines.skip(1)) {
    final low = ln.toLowerCase();
    if (['итого', 'total', 'сумма', 'ндс', 'всего'].any(low.contains)) continue;
    var m = RegExp(r'([\d\s]+[.,]\d{2})\s*(?:руб|₽|rur)?\s*$', caseSensitive: false).firstMatch(ln);
    m ??= RegExp(r'(\d+(?:[.,]\d{2})?)\s*(?:руб|₽)?\s*$', caseSensitive: false).firstMatch(ln);
    if (m == null) continue;
    final price = _parsePriceToken(m.group(1)!);
    if (price == null || price <= 0) continue;
    final namePart = ln.substring(0, m.start).replaceAll(RegExp(r'[ -:\t]+$'), '');
    if (namePart.length < 2) continue;
    items.add(ParsedReceiptItem(rawName: namePart, unitPrice: price));
  }
  return ParsedReceipt(supplierName: supplierName, items: items);
}

double receiptPriceToPiece(double unitPrice, String receiptUnit, double unitsPerPack) {
  if (unitPrice <= 0) return 0;
  final ru = receiptUnit.toLowerCase();
  if (ru == 'pack' || ru == 'уп' || ru == 'упак') {
    final n = unitsPerPack <= 0 ? 1.0 : unitsPerPack;
    if (n > 1) return double.parse((unitPrice / n).toStringAsFixed(4));
  }
  return unitPrice;
}

ParsedReceipt parseSaturnV1(String text, ReceiptTemplate tpl) {
  final items = <ParsedReceiptItem>[];
  final skip = ((tpl.data['skip_articles'] as List?) ?? []).map((e) => e.toString()).toSet();
  final config = (tpl.data['article_config'] as Map?)?.cast<String, dynamic>() ?? {};
  for (final code in config.keys) {
    if (skip.contains(code)) continue;
    final cfg = (config[code] as Map).cast<String, dynamic>();
    final itemKey = cfg['item_key'] as String?;
    if (itemKey == null) continue;
    final m = RegExp(
      '-${RegExp.escape(code)}[\\s\\S]*?'
      r'(\d+)\s+\S+[\s\n]*(\d+(?:[.,]\d+)?)\s+(\d+(?:[.,]\d+)?)',
    ).firstMatch(text);
    if (m == null) continue;
    final receiptPrice = double.tryParse(m.group(2)!.replaceAll(',', '.'));
    if (receiptPrice == null || receiptPrice <= 0) continue;
    final ru = cfg['receipt_unit'] as String? ?? 'piece';
    final upp = (cfg['units_per_pack'] as num?)?.toDouble() ?? defaultUnitsPerPack(itemKey).toDouble();
    final piece = receiptPriceToPiece(receiptPrice, ru, upp);
    final entry = catalogByItemKey(itemKey);
    items.add(ParsedReceiptItem(
      rawName: entry?.displayName ?? 'Сат-$code',
      unitPrice: piece,
      itemKey: itemKey,
      receiptUnit: ru,
      unitsPerPack: upp,
      unitPriceReceipt: receiptPrice,
    ));
  }
  final name = (tpl.data['supplier'] as Map?)?['fixed_name'] as String? ?? 'Сатурн';
  return ParsedReceipt(supplierName: name, items: items);
}

Future<(ParsedReceipt parsed, Map<String, dynamic>? meta)> parseReceiptTextSmart(String text) async {
  final templates = await loadReceiptTemplates();
  final (tpl, score) = detectTemplate(text, templates);
  if (tpl != null && tpl.customParser == 'saturn_v1') {
    return (parseSaturnV1(text, tpl), {'template_id': tpl.id, 'template_name': tpl.name, 'score': score});
  }
  if (tpl != null) {
    final parsed = parseReceiptText(text);
    final fixed = (tpl.data['supplier'] as Map?)?['fixed_name'] as String?;
    return (
      ParsedReceipt(supplierName: fixed ?? parsed.supplierName, items: parsed.items),
      {'template_id': tpl.id, 'template_name': tpl.name, 'score': score},
    );
  }
  return (parseReceiptText(text), null);
}

AliasHit? matchReceiptRow(ParsedReceiptItem item) {
  if (item.itemKey != null) {
    return AliasHit(
      itemKey: item.itemKey!,
      receiptUnit: item.receiptUnit,
      unitsPerPack: item.unitsPerPack,
      productName: catalogByItemKey(item.itemKey!)?.displayName,
    );
  }
  return matchProductAlias(item.rawName);
}

Future<ReceiptApplyResult> applyParsedReceipt(
  SupplierRepository repo,
  ParsedReceipt parsed, {
  bool merge = true,
}) async {
  final supplier = await repo.getOrCreateSupplier(parsed.supplierName);
  final existing = await repo.listPrices(supplier.id!);
  final byKey = {for (final p in existing) p.itemKey: p};

  final matched = <Map<String, dynamic>>[];
  final unmatched = <ParsedReceiptItem>[];

  for (final row in parsed.items) {
    final alias = matchReceiptRow(row);
    if (alias == null) {
      unmatched.add(row);
      continue;
    }
    final entry = catalogByItemKey(alias.itemKey);
    final ru = alias.receiptUnit ?? row.receiptUnit ?? defaultReceiptUnit(alias.itemKey);
    final upp = alias.unitsPerPack ??
        row.unitsPerPack ??
        defaultUnitsPerPack(alias.itemKey).toDouble();
    final cost = row.itemKey != null
        ? row.unitPrice
        : receiptPriceToPiece(row.unitPriceReceipt ?? row.unitPrice, ru, upp);
    final client = cost > 0 ? double.parse((cost * 1.1).toStringAsFixed(2)) : 0.0;
    final price = SupplierPrice(
      itemKey: alias.itemKey,
      productName: alias.productName ?? entry?.displayName ?? row.rawName,
      unitPriceCost: cost,
      unitPriceClient: client,
      receiptUnit: 'piece',
      unitsPerPack: upp,
    );
    if (merge && byKey.containsKey(alias.itemKey) && price.productName.isEmpty) {
      price.productName = byKey[alias.itemKey]!.productName;
    }
    await repo.upsertPrice(supplier.id!, price);
    matched.add({
      'raw_name': row.rawName,
      'item_key': alias.itemKey,
      'catalog_name': entry?.displayName ?? alias.itemKey,
      'unit_price_cost': cost,
      'unit_price_client': client,
    });
  }

  return ReceiptApplyResult(
    supplierId: supplier.id!,
    supplierName: supplier.name,
    matched: matched,
    unmatched: unmatched,
  );
}

Future<String?> pickReceiptText() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'txt', 'text'],
    allowMultiple: false,
  );
  if (files.isEmpty) return null;
  final f = files.first;
  final name = f.name.toLowerCase();
  final bytes = await f.readAsBytes();
  if (name.endsWith('.pdf')) {
    final text = extractPdfTextRough(bytes);
    return text.trim().isEmpty ? null : text;
  }
  return utf8.decode(bytes, allowMalformed: true);
}
