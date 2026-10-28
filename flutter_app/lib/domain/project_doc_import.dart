import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'documentation_model.dart';
import 'material_catalog.dart';
import 'office_doc_reader.dart';
import 'product_aliases.dart';
import 'project_price_resolver.dart';
import 'project_doc_format_detector.dart';
import 'ks2_work_scope.dart';
import 'receipt_import.dart';
import 'receipt_templates.dart';

double? parsePriceToken(String s) {
  final cleaned = s.replaceAll(' ', '').replaceAll(',', '.');
  final m = RegExp(r'(\d+(?:\.\d{1,2})?)').firstMatch(cleaned);
  if (m == null) return null;
  return double.tryParse(m.group(1)!);
}

/// Fields extracted from uploaded contract / estimate / price list.
class ParsedProjectDocument {
  ParsedProjectDocument({
    this.customer = '',
    this.executor = '',
    this.objectName = '',
    this.address = '',
    this.contractNumber = '',
    this.estimateNumber = '',
    this.customerInn = '',
    this.prices = const [],
    this.sourceHint = '',
    this.warning = '',
    this.format = '',
  });

  final String customer;
  final String executor;
  final String objectName;
  final String address;
  final String contractNumber;
  final String estimateNumber;
  final String customerInn;
  final List<ProjectPriceLine> prices;
  final String sourceHint;
  final String warning;
  final String format;

  bool get hasStampFields =>
      customer.isNotEmpty ||
      executor.isNotEmpty ||
      objectName.isNotEmpty ||
      address.isNotEmpty ||
      contractNumber.isNotEmpty ||
      estimateNumber.isNotEmpty;

  bool get hasPrices => prices.isNotEmpty;

  bool get ok => (hasStampFields || hasPrices) && warning.isEmpty;
}

class ProjectDocParseResult {
  const ProjectDocParseResult({
    required this.parsed,
    this.filename,
    this.meta = const AdaptiveParseMeta(),
  });

  final ParsedProjectDocument parsed;
  final String? filename;
  final AdaptiveParseMeta meta;
}

String? _fieldAfterLabel(String text, List<String> labels) {
  for (final label in labels) {
    final m = RegExp(
      '${RegExp.escape(label)}\\s*[:№#]?\\s*(.+)',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(text);
    if (m != null) {
      final v = m.group(1)!.split('\n').first.trim();
      if (v.isNotEmpty && v.length < 200) return v;
    }
  }
  return null;
}

/// Parse tabular price rows (Excel / CSV / smeta export).
List<ProjectPriceLine> parsePriceTableRows(List<List<String>> rows) {
  if (rows.isEmpty) return [];

  int? headerIdx;
  int? colKey, colCode, colName, colUnit, colPrice;

  for (var r = 0; r < rows.length && r < 40; r++) {
    final header = rows[r].map((c) => c.toLowerCase().trim()).toList();
    var hits = 0;
    int? k, c, n, u, p;
    for (var i = 0; i < header.length; i++) {
      final h = header[i];
      if (k == null && (h.contains('match_key') || h == 'key' || h.contains('ключ'))) k = i;
      if (c == null && (h.contains('обосн') || h.contains('шифр') || h.contains('код'))) c = i;
      if (n == null &&
          (h.contains('наимен') || h.contains('name') || h.contains('работ'))) {
        n = i;
        hits++;
      }
      if (u == null && (h.contains('ед') || h.contains('unit'))) {
        u = i;
        hits++;
      }
      if (p == null &&
          (h.contains('расцен') ||
              h.contains('цена за ед') ||
              (h.contains('цен') && !h.contains('сумм') && !h.contains('стоим')) ||
              h.contains('price'))) {
        p = i;
        hits++;
      }
    }
    if (n != null && p != null && hits >= 2) {
      headerIdx = r;
      colKey = k;
      colCode = c;
      colName = n;
      colUnit = u;
      colPrice = p;
      break;
    }
  }

  if (headerIdx == null) {
    return _parsePriceCsv(_rowsToDelimitedText(rows));
  }

  final out = <ProjectPriceLine>[];
  for (final row in rows.skip(headerIdx + 1)) {
    if (row.isEmpty) continue;
    final name = colName! < row.length ? row[colName].trim() : '';
    if (name.length < 2) continue;
    final low = name.toLowerCase();
    if (['итого', 'всего', 'ндс', 'раздел', 'итог'].any(low.startsWith)) continue;

    final priceRaw = colPrice! < row.length ? row[colPrice] : '';
    final price = parsePriceToken(priceRaw);
    if (price == null || price <= 0) continue;

    var key = colKey != null && colKey < row.length ? row[colKey].trim() : '';
    if (key.isEmpty && colCode != null && colCode < row.length) {
      key = row[colCode].trim();
    }
    key = key.isEmpty ? _guessMatchKey(name) : key;

    final unit = colUnit != null && colUnit < row.length && row[colUnit].trim().isNotEmpty
        ? row[colUnit].trim()
        : 'шт';

    out.add(ProjectPriceLine(matchKey: key, name: name, unit: unit, unitPrice: price));
  }
  return out;
}

String _rowsToDelimitedText(List<List<String>> rows) {
  final buf = StringBuffer();
  for (final row in rows) {
    buf.writeln(row.join(';'));
  }
  return buf.toString();
}

List<ProjectPriceLine> _parsePriceCsv(String text) {
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return [];

  final sep = lines.first.contains(';')
      ? ';'
      : lines.first.contains('\t')
          ? '\t'
          : ',';
  final header = lines.first.toLowerCase().split(sep).map((c) => c.trim()).toList();

  int? colKey, colName, colUnit, colPrice;
  for (var i = 0; i < header.length; i++) {
    final h = header[i];
    if (colKey == null && (h.contains('key') || h.contains('код') || h.contains('ключ'))) {
      colKey = i;
    }
    if (colName == null &&
        (h.contains('наимен') || h.contains('name') || h.contains('работ'))) {
      colName = i;
    }
    if (colUnit == null && (h.contains('ед') || h.contains('unit'))) colUnit = i;
    if (colPrice == null &&
        (h.contains('цен') || h.contains('price') || h.contains('расцен'))) {
      colPrice = i;
    }
  }

  final out = <ProjectPriceLine>[];
  final start = (colName != null || colPrice != null) ? 1 : 0;
  for (final ln in lines.skip(start)) {
    final cols = ln.split(sep).map((c) => c.trim()).toList();
    if (cols.isEmpty) continue;

    String name;
    String? key;
    String unit = 'шт';
    double? price;

    if (colName != null && colName < cols.length) {
      name = cols[colName];
      if (colKey != null && colKey < cols.length) key = cols[colKey];
      if (colUnit != null && colUnit < cols.length && cols[colUnit].isNotEmpty) {
        unit = cols[colUnit];
      }
      if (colPrice != null && colPrice < cols.length) {
        price = parsePriceToken(cols[colPrice]);
      }
    } else if (cols.length >= 2) {
      name = cols[0];
      price = parsePriceToken(cols.last);
      if (cols.length >= 3) unit = cols[1];
      if (cols.length >= 4) key = cols[0];
    } else {
      continue;
    }

    if (name.length < 2 || price == null || price <= 0) continue;
    key ??= _guessMatchKey(name);
    out.add(ProjectPriceLine(matchKey: key, name: name, unit: unit, unitPrice: price));
  }
  return out;
}

String _guessMatchKey(String name) => guessMatchKeyForImport(name);

List<ProjectPriceLine> _parsePriceLinesFromText(String text) {
  final receipt = parseReceiptText(text);
  final out = <ProjectPriceLine>[];
  for (final item in receipt.items) {
    final key = _guessMatchKey(item.rawName);
    out.add(ProjectPriceLine(
      matchKey: key,
      name: item.rawName,
      unitPrice: item.unitPrice,
    ));
  }
  return out;
}

/// Try to read stamp fields from spreadsheet header rows (label in col A, value in col B).
({
  String customer,
  String executor,
  String objectName,
  String address,
  String contractNumber,
  String estimateNumber,
}) _stampFromTableRows(List<List<String>> rows) {
  var customer = '';
  var executor = '';
  var objectName = '';
  var address = '';
  var contractNumber = '';
  var estimateNumber = '';

  for (final row in rows.take(25)) {
    if (row.isEmpty) continue;
    final label = row.first.toLowerCase().trim();
    final value = row.length > 1 ? row[1].trim() : '';
    if (value.isEmpty) continue;
    if (label.contains('заказчик')) customer = value;
    if (label.contains('исполнит') || label.contains('подрядчик')) executor = value;
    if (label.contains('объект')) objectName = value;
    if (label.contains('адрес')) address = value;
    if (label.contains('договор') || label.contains('контракт')) contractNumber = value;
    if (label.contains('смет')) estimateNumber = value;
  }
  return (
    customer: customer,
    executor: executor,
    objectName: objectName,
    address: address,
    contractNumber: contractNumber,
    estimateNumber: estimateNumber,
  );
}

/// Parse uploaded document into stamp fields and project price lines.
ParsedProjectDocument parseProjectDocument(
  String text, {
  String? filename,
  List<List<String>> tableRows = const [],
  String format = '',
  String warning = '',
}) {
  if (warning.isNotEmpty && text.isEmpty && tableRows.isEmpty) {
    return ParsedProjectDocument(warning: warning, sourceHint: filename ?? '', format: format);
  }

  final lowName = filename?.toLowerCase() ?? '';
  final fromTable = tableRows.isNotEmpty ? _stampFromTableRows(tableRows) : null;

  if (lowName.endsWith('.csv') || (tableRows.isEmpty && _looksLikeCsv(text))) {
    final prices = tableRows.isNotEmpty
        ? parsePriceTableRows(tableRows)
        : _parsePriceCsv(text);
    return ParsedProjectDocument(
      prices: prices,
      sourceHint: filename ?? 'CSV',
      format: format.isEmpty ? 'csv' : format,
      warning: warning,
    );
  }

  final customer = _fieldAfterLabel(text, ['Заказчик', 'Customer']) ??
      fromTable?.customer ??
      '';
  final executor = _fieldAfterLabel(text, [
        'Исполнитель',
        'Подрядчик',
        'Генподрядчик',
        'Contractor',
      ]) ??
      fromTable?.executor ??
      '';
  final objectName = _fieldAfterLabel(text, ['Объект', 'Object', 'Наименование объекта']) ??
      fromTable?.objectName ??
      '';
  final address = _fieldAfterLabel(text, ['Адрес', 'Address', 'Место выполнения работ']) ??
      fromTable?.address ??
      '';
  final contractNumber =
      _fieldAfterLabel(text, ['Договор', 'Контракт']) ?? fromTable?.contractNumber ?? '';
  final estimateNumber = _fieldAfterLabel(text, [
        'Смета',
        'Локальная смета',
        'Сметная документация',
      ]) ??
      fromTable?.estimateNumber ??
      '';

  final innMatch = RegExp(r'ИНН\s*[:№]?\s*(\d{10,12})', caseSensitive: false).firstMatch(text);
  final customerInn = innMatch?.group(1) ?? '';

  var prices = tableRows.isNotEmpty
      ? parsePriceTableRows(tableRows)
      : _parsePriceCsv(text);
  if (prices.isEmpty) prices = _parsePriceLinesFromText(text);

  return ParsedProjectDocument(
    customer: customer,
    executor: executor,
    objectName: objectName,
    address: address,
    contractNumber: contractNumber,
    estimateNumber: estimateNumber,
    customerInn: customerInn,
    prices: prices,
    sourceHint: filename ?? 'текст',
    format: format,
    warning: warning,
  );
}

bool _looksLikeCsv(String text) {
  final first = text.split('\n').first.trim();
  if (!first.contains(';') && !first.contains('\t')) return false;
  final low = first.toLowerCase();
  return low.contains('наимен') ||
      low.contains('цен') ||
      low.contains('price') ||
      low.contains('name');
}

/// Merge parsed data into project documentation (does not save to DB).
ProjectDocumentation applyParsedProjectDocument(
  ProjectDocumentation doc,
  ParsedProjectDocument parsed, {
  bool mergePrices = true,
}) {
  if (parsed.customer.isNotEmpty) doc.stamp.customer = parsed.customer;
  if (parsed.executor.isNotEmpty) doc.stamp.executor = parsed.executor;
  if (parsed.objectName.isNotEmpty) doc.stamp.objectName = parsed.objectName;
  if (parsed.address.isNotEmpty) doc.stamp.address = parsed.address;
  if (parsed.contractNumber.isNotEmpty) {
    doc.contract.contractNumber = parsed.contractNumber;
  }
  if (parsed.estimateNumber.isNotEmpty) {
    doc.contract.estimateNumber = parsed.estimateNumber;
  }
  if (parsed.customerInn.isNotEmpty) doc.contract.customerInn = parsed.customerInn;

  if (parsed.prices.isEmpty) return doc;

  if (!mergePrices) {
    doc.ks2Prices = List.from(parsed.prices);
  } else {
    final byKey = projectPricesByKey(doc.ks2Prices);
    for (final line in parsed.prices) {
      byKey[line.matchKey] = line;
    }
    doc.ks2Prices = byKey.values.toList();
  }

  final inferred = inferWorkScopesFromPriceLines(doc.ks2Prices);
  if (inferred.isNotEmpty) {
    doc.enabledWorkScopes = WorkScope.names(inferred);
  }
  return doc;
}

Future<ParsedProjectDocument> parseProjectDocumentBytes(
  Uint8List bytes,
  String filename,
) async {
  final low = filename.toLowerCase();
  if (low.endsWith('.pdf')) {
    final text = extractPdfTextRough(bytes);
    if (text.trim().isEmpty) {
      return ParsedProjectDocument(
        warning: 'Не удалось извлечь текст из PDF.',
        sourceHint: filename,
        format: 'pdf',
      );
    }
    return parseProjectDocument(text, filename: filename, format: 'pdf');
  }

  final office = readProjectDocumentBytes(bytes, filename);
  if (office.warning.isNotEmpty && !office.ok) {
    return ParsedProjectDocument(
      warning: office.warning,
      sourceHint: filename,
      format: office.format,
    );
  }

  final (adaptivePrices, meta) = await extractAdaptivePrices(
    text: office.text,
    tableRows: office.tableRows,
  );

  final base = parseProjectDocument(
    office.text,
    filename: filename,
    tableRows: office.tableRows,
    format: office.format,
    warning: office.warning,
  );

  if (adaptivePrices.isEmpty) return base;

  return ParsedProjectDocument(
    customer: base.customer,
    executor: base.executor,
    objectName: base.objectName,
    address: base.address,
    contractNumber: base.contractNumber,
    estimateNumber: base.estimateNumber,
    customerInn: base.customerInn,
    prices: adaptivePrices,
    sourceHint: filename,
    warning: base.warning,
    format: meta.formatId.isNotEmpty ? meta.formatId : base.format,
  );
}

Future<ProjectDocParseResult> parsePickedProjectDocument() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: projectDocImportExtensions,
    allowMultiple: false,
  );
  if (files.isEmpty) {
    return ProjectDocParseResult(parsed: ParsedProjectDocument());
  }
  final f = files.first;
  final name = f.name;
  final bytes = await f.readAsBytes();

  AdaptiveParseMeta meta = const AdaptiveParseMeta();
  if (!name.toLowerCase().endsWith('.pdf')) {
    final office = readProjectDocumentBytes(bytes, name);
    final extracted = await extractAdaptivePrices(
      text: office.text,
      tableRows: office.tableRows,
    );
    meta = extracted.$2;
  }

  final parsed = await parseProjectDocumentBytes(bytes, name);
  return ProjectDocParseResult(parsed: parsed, filename: name, meta: meta);
}

Future<String?> pickProjectDocText() async {
  final result = await parsePickedProjectDocument();
  if (result.filename == null) return null;
  if (result.parsed.warning.isNotEmpty && !result.parsed.hasStampFields) return null;
  return result.parsed.sourceHint;
}
