import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'cost_calculator.dart';
import 'documentation_model.dart';
import 'contract_document_model.dart';
import 'document_templates.dart';
import 'ks2_act_service.dart';
import 'models.dart';
import 'partner_profile.dart';
import 'work_rates_catalog.dart';
import 'xlsx_export.dart';
import 'xlsx_template_fill.dart';

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

void _dateParts(DateTime? d, void Function(String day, String month, String year) fn) {
  final dt = d ?? DateTime.now();
  fn('${dt.day.toString().padLeft(2, '0')}', '${dt.month.toString().padLeft(2, '0')}', '${dt.year}');
}

String _vatLabel(ProjectContractInfo contract) =>
    contract.vatExempt || contract.vatRatePercent <= 0 ? 'Без НДС' : 'без НДС';

void _fillAvangardHeader({
  required Map<String, XlsxCell> cells,
  required Project project,
  required ProjectDocumentation doc,
  required DocumentationStamp stamp,
}) {
  final contract = doc.contract;
  final customer = contract.customerName.isNotEmpty
      ? contract.customerName
      : stamp.customer.isNotEmpty
          ? stamp.customer
          : PartnerProfile.avangardCustomer.name;
  final buildSite = contract.buildSite.isNotEmpty
      ? contract.buildSite
      : stamp.address.isNotEmpty
          ? stamp.address
          : stamp.objectName.isEmpty
              ? project.name
              : stamp.objectName;
  final executor = stamp.executor.isNotEmpty
      ? stamp.executor
      : PartnerProfile.defaultGusev.executorLine;

  cells['W1'] = const XlsxCell.text('Унифицированная форма № КС- 2');
  cells['W2'] = const XlsxCell.text('Утверждена постановлением Госкомстата России');
  cells['W3'] = const XlsxCell.text('от 11.11.99 № 100');
  cells['AB4'] = const XlsxCell.text('0322005');

  cells['B7'] = const XlsxCell.text('Инвестор');
  cells['AB7'] = XlsxCell.text(contract.investorOkpo);
  cells['B9'] = const XlsxCell.text('Заказчик (Генподрядчик)');
  cells['G9'] = XlsxCell.text(customer);
  cells['AB9'] = XlsxCell.text(
    contract.customerOkpo.isNotEmpty
        ? contract.customerOkpo
        : PartnerProfile.avangardCustomer.okpo,
  );
  cells['B11'] = const XlsxCell.text('Подрядчик (Субподрядчик)');
  cells['H11'] = XlsxCell.text(executor);
  cells['B13'] = const XlsxCell.text('Стройка');
  cells['E13'] = XlsxCell.text(buildSite);
  cells['B15'] = const XlsxCell.text('Объект');
  final objectField = stamp.objectName.isNotEmpty
      ? stamp.objectName
      : project.name;
  cells['U15'] = XlsxCell.text(objectField);

  cells['R18'] = const XlsxCell.text('Договор подряда (контракт)');
  cells['AA18'] = const XlsxCell.text('номер');
  cells['AB18'] = XlsxCell.text(contract.contractNumber);
  cells['AA19'] = const XlsxCell.text('дата');
  _dateParts(contract.contractDate, (d, m, y) {
    cells['AB19'] = XlsxCell.text(d);
    cells['AD19'] = XlsxCell.text(m);
    cells['AE19'] = XlsxCell.text(y);
  });
}

Future<Uint8List?> _loadBlankBytes(String asset) async {
  try {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

Map<String, XlsxCell> _ks2Cells({
  required Project project,
  required ProjectDocumentation doc,
  required DocumentationStamp stamp,
  required List<Room> rooms,
  required int actNumber,
  required DateTime issueDate,
  required DateTime periodFrom,
  required DateTime periodTo,
  ContractDocumentSettings? settings,
  List<WorkRateCategory>? catalog,
  Map<String, SupplierPrice>? supplierPrices,
}) {
  final cfg = settings ?? doc.contractDocs;
  final lines = buildWorkLines(
    settings: cfg,
    rooms: rooms,
    floors: project.floors,
    catalog: catalog,
    supplierPrices: supplierPrices,
  );
  final total = linesTotal(lines);
  final cells = <String, XlsxCell>{};

  _fillAvangardHeader(cells: cells, project: project, doc: doc, stamp: stamp);

  // Value cells only — static labels already live in the blank.
  cells['N24'] = XlsxCell.number('$actNumber');
  cells['O24'] = XlsxCell.text(_fmtDate(issueDate));
  cells['U24'] = XlsxCell.text(_fmtDate(periodFrom));
  cells['Y24'] = XlsxCell.text(_fmtDate(periodTo));

  // Data starts at row 32. Single mode → one row; byRoom/custom → all lines.
  final writeLines = <ContractWorkLine>[];
  if (lines.isEmpty) {
    // nothing
  } else if (cfg.lineMode == ProposalLineMode.single && lines.length > 1) {
    final qty = lines.fold<double>(0, (s, l) => s + l.quantity);
    writeLines.add(
      ContractWorkLine(
        name: cfg.workNameWithScope(),
        unit: 'м2',
        quantity: qty,
        unitPrice: qty > 0 ? total / qty : 0,
        estimatePos: '1',
      ),
    );
  } else {
    writeLines.addAll(lines);
  }

  for (var i = 0; i < writeLines.length; i++) {
    final line = writeLines[i];
    final row = 32 + i;
    final pos = line.estimatePos.isEmpty ? '${i + 1}' : line.estimatePos;
    cells['A$row'] = XlsxCell.number('${i + 1}');
    cells['C$row'] = XlsxCell.number(pos);
    cells['F$row'] = XlsxCell.text(line.name);
    cells['O$row'] = XlsxCell.text(line.unit);
    cells['S$row'] = XlsxCell.number(line.quantity.toStringAsFixed(2));
    cells['W$row'] = XlsxCell.number(line.unitPrice.toStringAsFixed(2));
    cells['AB$row'] = XlsxCell.number(line.lineSum.toStringAsFixed(2));
  }

  final rowShift = writeLines.length > 1 ? writeLines.length - 1 : 0;
  // Totals / signatures shift when we clone data rows.
  cells['AB${35 + rowShift}'] = XlsxCell.number(total.toStringAsFixed(2));
  cells['AB${36 + rowShift}'] = XlsxCell.text(_vatLabel(doc.contract));
  cells['AB${37 + rowShift}'] = XlsxCell.number(total.toStringAsFixed(2));

  final customerShort = doc.contract.customerName.contains('Авангард')
      ? 'ООО "ГК Авангард"'
      : (stamp.customer.isNotEmpty ? stamp.customer : 'Заказчик');
  cells['A${38 + rowShift}'] = XlsxCell.text(customerShort);
  cells['A${43 + rowShift}'] = XlsxCell.text(
    stamp.executor.isNotEmpty ? PartnerProfile.defaultGusev.shortName : 'Подрядчик',
  );

  return cells;
}

/// How many data rows the KS-2 blank must expand to for [settings]/rooms].
int ks2DataRowCount({
  required ContractDocumentSettings settings,
  required Iterable<Room> rooms,
  List<ProjectFloor> floors = const [],
  List<WorkRateCategory>? catalog,
}) {
  final lines = buildWorkLines(
    settings: settings,
    rooms: rooms,
    floors: floors,
    catalog: catalog,
  );
  if (lines.isEmpty) return 1;
  if (settings.lineMode == ProposalLineMode.single) return 1;
  return lines.length;
}

/// GOST-style KS-2: fill Avangard `.xlsx` blank; sparse fallback if blank missing.
Future<Uint8List> buildOfficialKs2Xlsx({
  required Project project,
  required ProjectDocumentation doc,
  required DocumentationStamp stamp,
  required List<Room> rooms,
  required int actNumber,
  required DateTime issueDate,
  required DateTime periodFrom,
  required DateTime periodTo,
  ContractDocumentSettings? settings,
  Uint8List? blankBytes,
  Map<String, SupplierPrice>? supplierPrices,
}) async {
  final catalog = await WorkRatesCatalogStore.ensureLoaded();
  final cells = _ks2Cells(
    project: project,
    doc: doc,
    stamp: stamp,
    rooms: rooms,
    actNumber: actNumber,
    issueDate: issueDate,
    periodFrom: periodFrom,
    periodTo: periodTo,
    settings: settings,
    catalog: catalog,
    supplierPrices: supplierPrices,
  );
  final blank = blankBytes ?? await _loadBlankBytes(bundledKs2BlankAsset);
  if (blank != null) {
    try {
      final cfg = settings ?? doc.contractDocs;
      final dataRows = ks2DataRowCount(
        settings: cfg,
        rooms: rooms,
        floors: project.floors,
        catalog: catalog,
      );
      return fillXlsxTemplate(
        templateBytes: blank,
        cells: cells,
        expandTemplateRow: 32,
        expandCount: dataRows,
      );
    } catch (e, st) {
      assert(() {
        // ignore: avoid_print
        print('buildOfficialKs2Xlsx fill failed: $e\n$st');
        return true;
      }());
      // Fall through to sparse writer.
    }
  }
  return buildSparseXlsx(sheetName: 'КС-2', cells: cells);
}

Map<String, XlsxCell> _ks3Cells({
  required Project project,
  required ProjectDocumentation doc,
  required DocumentationStamp stamp,
  required int documentNumber,
  required DateTime issueDate,
  required DateTime periodFrom,
  required DateTime periodTo,
  required List<Ks2ActRecord> acts,
  ContractDocumentSettings? settings,
}) {
  final cfg = settings ?? doc.contractDocs;
  final cells = <String, XlsxCell>{};
  final contract = doc.contract;
  final customer = contract.customerName.isNotEmpty
      ? contract.customerName
      : stamp.customer.isNotEmpty
          ? stamp.customer
          : PartnerProfile.avangardCustomer.name;
  final buildSite = contract.buildSite.isNotEmpty
      ? contract.buildSite
      : stamp.address.isNotEmpty
          ? stamp.address
          : project.name;
  final executor = stamp.executor.isNotEmpty
      ? stamp.executor
      : PartnerProfile.defaultGusev.executorLine;

  cells['AK7'] = XlsxCell.text(contract.investorOkpo);
  cells['M9'] = XlsxCell.text(customer);
  cells['AK9'] = XlsxCell.text(
    contract.customerOkpo.isNotEmpty
        ? contract.customerOkpo
        : PartnerProfile.avangardCustomer.okpo,
  );
  cells['N11'] = XlsxCell.text(executor);
  cells['E13'] = XlsxCell.text(buildSite);
  cells['AP16'] = XlsxCell.text(contract.contractNumber);
  _dateParts(contract.contractDate, (d, m, y) {
    cells['AP17'] = XlsxCell.text(d);
    cells['AT17'] = XlsxCell.text(m);
    cells['AX17'] = XlsxCell.text(y);
  });

  cells['X22'] = XlsxCell.number('$documentNumber');
  cells['AG22'] = XlsxCell.text(_fmtDate(issueDate));
  cells['AR22'] = XlsxCell.text(_fmtDate(periodFrom));
  cells['AW22'] = XlsxCell.text(_fmtDate(periodTo));

  final ledgerRows = buildKs3LedgerRows(
    acts: activeKs2Acts(acts),
    periodFrom: periodFrom,
    periodTo: periodTo,
  );
  final periodTotal = ledgerRows.fold<double>(0, (s, r) => s + r.periodSum);
  final cumulativeTotal = ledgerRows.fold<double>(0, (s, r) => s + r.cumulativeSum);
  final workName = cfg.workNameWithScope();

  cells['AE29'] = XlsxCell.number(cumulativeTotal.toStringAsFixed(2));
  cells['AL29'] = XlsxCell.number(cumulativeTotal.toStringAsFixed(2));
  cells['AT29'] = XlsxCell.number(periodTotal.toStringAsFixed(2));
  cells['E32'] = XlsxCell.text(workName);
  cells['AE32'] = XlsxCell.number(cumulativeTotal.toStringAsFixed(2));
  cells['AL32'] = XlsxCell.number(cumulativeTotal.toStringAsFixed(2));
  cells['AT32'] = XlsxCell.number(periodTotal.toStringAsFixed(2));
  cells['AT33'] = XlsxCell.number(periodTotal.toStringAsFixed(2));
  cells['AT34'] = XlsxCell.text(_vatLabel(contract));
  cells['AT35'] = XlsxCell.number(periodTotal.toStringAsFixed(2));

  return cells;
}

Future<Uint8List> buildOfficialKs3Xlsx({
  required Project project,
  required ProjectDocumentation doc,
  required DocumentationStamp stamp,
  required int documentNumber,
  required DateTime issueDate,
  required DateTime periodFrom,
  required DateTime periodTo,
  required List<Ks2ActRecord> acts,
  ContractDocumentSettings? settings,
  Uint8List? blankBytes,
}) async {
  final cells = _ks3Cells(
    project: project,
    doc: doc,
    stamp: stamp,
    documentNumber: documentNumber,
    issueDate: issueDate,
    periodFrom: periodFrom,
    periodTo: periodTo,
    acts: acts,
    settings: settings,
  );
  final blank = blankBytes ?? await _loadBlankBytes(bundledKs3BlankAsset);
  if (blank != null) {
    try {
      return fillXlsxTemplate(templateBytes: blank, cells: cells);
    } catch (_) {}
  }
  return buildSparseXlsx(sheetName: 'КС-3', cells: cells);
}

Uint8List _workLinesSimpleXlsx({
  required String title,
  required String sheetName,
  required Project project,
  required ProjectDocumentation doc,
  required DocumentationStamp stamp,
  required List<Room> rooms,
  ContractDocumentSettings? settings,
  List<WorkRateCategory>? catalog,
  Map<String, SupplierPrice>? supplierPrices,
}) {
  final cfg = settings ?? doc.contractDocs;
  final lines = buildWorkLines(
    settings: cfg,
    rooms: rooms,
    floors: project.floors,
    catalog: catalog,
    supplierPrices: supplierPrices,
  );
  final total = linesTotal(lines);
  final partner = PartnerProfile.defaultGusev;

  final rows = <List<String>>[
    [title],
    ['Объект', stamp.objectName.isEmpty ? project.name : stamp.objectName],
    if (stamp.customer.isNotEmpty) ['Заказчик', stamp.customer],
    if (stamp.address.isNotEmpty) ['Адрес', stamp.address],
    ['Исполнитель', stamp.executor.isNotEmpty ? stamp.executor : partner.executorLine],
    ['Дата', _fmtDate(stamp.issueDate)],
    [],
    ['№', 'Наименование работ', 'Ед.', 'Кол-во', 'Цена, ₽', 'Сумма, ₽'],
  ];

  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    rows.add([
      '${i + 1}',
      l.name,
      l.unit,
      l.quantity.toStringAsFixed(2),
      l.unitPrice.toStringAsFixed(2),
      l.lineSum.toStringAsFixed(2),
    ]);
  }
  rows.add([]);
  rows.add(['', '', '', '', 'Итого:', total.toStringAsFixed(2)]);
  rows.add(['', '', '', '', 'НДС:', _vatLabel(doc.contract)]);

  return buildSimpleXlsx(sheetName: sheetName, rows: rows);
}

Uint8List buildCommercialProposalXlsx({
  required Project project,
  required ProjectDocumentation doc,
  required DocumentationStamp stamp,
  required List<Room> rooms,
  ContractDocumentSettings? settings,
  List<WorkRateCategory>? catalog,
  Map<String, SupplierPrice>? supplierPrices,
}) =>
    _workLinesSimpleXlsx(
      title: 'Коммерческое предложение',
      sheetName: 'KP',
      project: project,
      doc: doc,
      stamp: stamp,
      rooms: rooms,
      settings: settings,
      catalog: catalog,
      supplierPrices: supplierPrices,
    );

/// Simplified KS-2 table (work lines) when form style is not Avangard blank.
Uint8List buildSimpleKs2WorkLinesXlsx({
  required Project project,
  required ProjectDocumentation doc,
  required DocumentationStamp stamp,
  required List<Room> rooms,
  required int actNumber,
  ContractDocumentSettings? settings,
  List<WorkRateCategory>? catalog,
  Map<String, SupplierPrice>? supplierPrices,
}) =>
    _workLinesSimpleXlsx(
      title: 'КС-2 · акт № $actNumber',
      sheetName: 'KS-2',
      project: project,
      doc: doc,
      stamp: stamp,
      rooms: rooms,
      settings: settings,
      catalog: catalog,
      supplierPrices: supplierPrices,
    );

String buildSimpleActText({
  required Project project,
  required ProjectDocumentation doc,
  required DocumentationStamp stamp,
  required List<Room> rooms,
  required int actNumber,
  ContractDocumentSettings? settings,
}) {
  final cfg = settings ?? doc.contractDocs;
  final lines = buildWorkLines(
    settings: cfg,
    rooms: rooms,
    floors: project.floors,
  );
  final total = linesTotal(lines);
  final buf = StringBuffer()
    ..writeln('АКТ выполненных работ № $actNumber')
    ..writeln('Дата: ${_fmtDate(stamp.issueDate)}')
    ..writeln('')
    ..writeln('Объект: ${stamp.objectName.isEmpty ? project.name : stamp.objectName}')
    ..writeln('Заказчик: ${stamp.customer}')
    ..writeln('Исполнитель: ${stamp.executor}')
    ..writeln('')
    ..writeln('Выполнены следующие работы:');

  for (final line in lines) {
    buf.writeln(
      '• ${line.name}: ${line.quantity.toStringAsFixed(2)} ${line.unit} × '
      '${line.unitPrice.toStringAsFixed(2)} = ${line.lineSum.toStringAsFixed(2)} ₽',
    );
  }
  buf
    ..writeln('')
    ..writeln('Итого: ${total.toStringAsFixed(2)} ₽ (${_vatLabel(doc.contract)})')
    ..writeln('')
    ..writeln('Заказчик: _________________')
    ..writeln('Исполнитель: _________________');
  return buf.toString();
}

/// Apply default partner requisites + optional Авангард customer to project doc.
ProjectDocumentation applyPartnerDefaults(
  ProjectDocumentation doc, {
  PartnerProfile partner = PartnerProfile.defaultGusev,
  bool fillAvangardCustomer = false,
}) {
  doc.stamp = partner.applyToStamp(doc.stamp);
  normalizeStampCustomerAddress(doc.stamp);
  normalizeContractCustomerAddress(doc.contract);
  if (fillAvangardCustomer) {
    doc.stamp = doc.stamp.copyWith(
      customer: PartnerProfile.avangardCustomer.name,
      address: PartnerProfile.avangardCustomer.address,
    );
    doc.contract.customerName = PartnerProfile.avangardCustomer.name;
    doc.contract.customerOkpo = PartnerProfile.avangardCustomer.okpo;
    if (doc.contract.buildSite.trim().isEmpty) {
      doc.contract.buildSite = PartnerProfile.avangardCustomer.address;
    }
  }
  if (doc.contractDocs.unifiedPricePerM2 <= 0) {
    doc.contractDocs.unifiedPricePerM2 = 700;
  }
  return doc;
}
