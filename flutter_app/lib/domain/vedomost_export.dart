import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'cost_calculator.dart';
import 'document_qr.dart';
import 'documentation_model.dart';
import 'finish_vedomost.dart';
import 'materials_calculator.dart';
import 'models.dart';
import 'pdf_fonts.dart';
import 'project_materials.dart';
import 'project_price_resolver.dart';
import 'xlsx_export.dart';

const _vedomostSectionOrder = [
  'Потолок',
  'Стены',
  'Пол',
  'Расходники',
  'Другие работы',
];

String _sectionBanner(String title) => '—— $title ——';

String _formatVedomostLine(String name, String quantity, String unit, {int? index}) {
  final qty = unit.trim().isEmpty ? quantity : '$quantity $unit'.trim();
  if (index != null) {
    final n = index.toString().padLeft(2, '0');
    return '$n  $name · $qty';
  }
  return '$name · $qty';
}

void _writeVedomostHeader(
  StringBuffer buf, {
  required Project project,
  required DocumentationStamp stamp,
  required String roomLabel,
}) {
  buf
    ..writeln('Ведомость материалов')
    ..writeln('Объект: ${stamp.objectName.isEmpty ? project.name : stamp.objectName}')
    ..writeln('Помещение: $roomLabel')
    ..writeln('Дата: ${_date(stamp.issueDate)}');
  if (stamp.customer.isNotEmpty) buf.writeln('Заказчик: ${stamp.customer}');
  if (stamp.address.isNotEmpty) buf.writeln('Адрес: ${stamp.address}');
  if (stamp.executor.isNotEmpty) buf.writeln('Исполнитель: ${stamp.executor}');
  buf.writeln('');
}

void _writeSectionedFinishLines(
  StringBuffer buf,
  List<FinishVedomostLine> finish, {
  bool skipCeilingPurchaseDup = true,
}) {
  final bySection = <String, List<FinishVedomostLine>>{};
  for (final f in finish) {
    if (skipCeilingPurchaseDup &&
        f.section == 'Потолок' &&
        f.name.contains('закупка')) {
      continue;
    }
    bySection.putIfAbsent(f.section, () => []).add(f);
  }
  for (final section in _vedomostSectionOrder) {
    final lines = bySection.remove(section);
    if (lines == null || lines.isEmpty) continue;
    buf.writeln(_sectionBanner(section));
    var i = 1;
    for (final f in lines) {
      buf.writeln(_formatVedomostLine(f.name, f.quantity, f.unit, index: i++));
    }
    buf.writeln('');
  }
  for (final e in bySection.entries) {
    if (e.value.isEmpty) continue;
    buf.writeln(_sectionBanner(e.key));
    var i = 1;
    for (final f in e.value) {
      buf.writeln(_formatVedomostLine(f.name, f.quantity, f.unit, index: i++));
    }
    buf.writeln('');
  }
}

/// Build plain-text vedomost for one room — sections: ceiling → walls → floor.
String buildVedomostText({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
}) {
  final buf = StringBuffer();
  _writeVedomostHeader(
    buf,
    project: project,
    stamp: stamp,
    roomLabel: room.name,
  );
  if (!room.hasLayout) {
    buf.writeln('Нет закрытого чертежа — сначала замкните контур в редакторе.');
    return buf.toString();
  }

  final finish = buildFinishVedomostLines(room, project: project);
  final includeCeiling = room.finishIncludeCeiling;
  if (includeCeiling) {
    final ceiling = calculateRoomMaterials(room, project);
    final (ceilingType, susp, cell) = roomEffectiveConfig(room, project);
    final area = MaterialsCalculator.roomAreaM2(room.walls);
    final purchase = ceilingPurchaseCount(room);
    final cellPart =
        ceilingType == 'Грильято' || ceilingType == 'GL' ? ' / $cell' : '';
    buf
      ..writeln('Площадь: ${area.toStringAsFixed(2)} м²')
      ..writeln('Потолок: $ceilingType / $susp$cellPart')
      ..writeln('')
      ..writeln(_sectionBanner('Потолок'))
      ..writeln(_formatVedomostLine('Плиты/кассеты — закупка', '$purchase', 'шт'));
    var i = 1;
    for (final e in sortedMaterialEntries(ceiling)) {
      buf.writeln(_formatVedomostLine(e.key, '${e.value}', 'шт', index: i++));
    }
    buf.writeln('');
    // Finish lines for ceiling already partly covered; still emit other sections
    // with ceiling finish meta under Потолок via sectioned writer — skip duplicate
    // purchase, keep type/cell lines under Потолок after BOM.
    final ceilingMeta = finish.where((f) => f.section == 'Потолок').toList();
    final rest = finish.where((f) => f.section != 'Потолок').toList();
    if (ceilingMeta.isNotEmpty) {
      for (final f in ceilingMeta) {
        if (f.name.contains('закупка')) continue;
        buf.writeln(_formatVedomostLine(f.name, f.quantity, f.unit, index: i++));
      }
      buf.writeln('');
    }
    _writeSectionedFinishLines(buf, rest, skipCeilingPurchaseDup: false);
  } else {
    _writeSectionedFinishLines(buf, finish);
  }
  return buf.toString().trimRight();
}

/// Project-wide vedomost (all rooms with layout).
String buildProjectVedomostText({
  required Project project,
  required DocumentationStamp stamp,
}) {
  final buf = StringBuffer();
  _writeVedomostHeader(
    buf,
    project: project,
    stamp: stamp,
    roomLabel: 'Все помещения',
  );
  final rooms = project.rooms.where((r) => r.hasLayout).toList();
  if (rooms.isEmpty) {
    buf.writeln('Нет помещений с чертежом.');
    return buf.toString();
  }
  buf.writeln('Помещений: ${rooms.length}');
  buf.writeln('');

  // One «Потолок» block: frame/BOM first, then finish meta (typed when mixed).
  final ceilingBom = aggregateCeilingComponentLines(project);
  final finish = aggregateFinishVedomostLines(project);
  final ceilingMeta = finish
      .where((f) => f.section == 'Потолок')
      .where(
        (f) =>
            !f.name.contains('закупка') &&
            !ceilingBom.any((c) => c.name == f.name),
      )
      .toList();
  if (ceilingBom.isNotEmpty || ceilingMeta.isNotEmpty) {
    buf.writeln(_sectionBanner('Потолок'));
    var i = 1;
    for (final f in ceilingBom) {
      buf.writeln(_formatVedomostLine(f.name, f.quantity, f.unit, index: i++));
    }
    for (final f in ceilingMeta) {
      buf.writeln(_formatVedomostLine(f.name, f.quantity, f.unit, index: i++));
    }
    buf.writeln('');
  }

  final rest = finish.where((f) => f.section != 'Потолок').toList();
  _writeSectionedFinishLines(buf, rest, skipCeilingPurchaseDup: false);
  return buf.toString().trimRight();
}

(String sku, String priceCol) _finishPriceCols(FinishVedomostLine line, Map<String, SupplierPrice>? prices) {
  if (prices == null) return ('', '');
  if (line.isLinkedMaterial) {
    final p = prices[line.linkedItemKey];
    if (p == null || p.unitPriceClient <= 0) {
      return (p?.supplierSku ?? '', '');
    }
    return (p.supplierSku, p.unitPriceClient.toStringAsFixed(2));
  }
  final key = switch (line.section) {
    'Пол' => 'finish_floor',
    'Стены' => 'finish_wall',
    'Потолок' => 'finish_ceiling',
    _ => 'finish_${line.section.toLowerCase()}',
  };
  final p = resolveFinishSupplierPrice(sectionKey: key, prices: prices);
  if (p == null || p.unitPriceClient <= 0) {
    return (p?.supplierSku ?? '', '');
  }
  return (p.supplierSku, p.unitPriceClient.toStringAsFixed(2));
}

String? _finishPriceKey(FinishVedomostLine line) {
  // Linked layer materials: priced only by supplier itemKey, not section work rate.
  if (line.isLinkedMaterial) return null;
  return switch (line.section) {
    'Пол' => 'finish_floor',
    'Стены' => 'finish_wall',
    'Потолок' => 'finish_ceiling',
    'Расходники' => null,
    _ => null,
  };
}

double? _parseFinishQty(FinishVedomostLine line) {
  final n = double.tryParse(line.quantity.replaceAll(',', '.').split('/').first.trim());
  return n;
}

(String sku, String priceCol) _priceCols(String calcKey, Map<String, SupplierPrice>? prices) {
  if (prices == null) return ('', '');
  final p = prices[calcKey];
  if (p == null || p.unitPriceClient <= 0) {
    return (p?.supplierSku ?? '', '');
  }
  return (p.supplierSku, p.unitPriceClient.toStringAsFixed(2));
}

/// Vedomost with optional supplier SKU and client prices.
String buildVedomostTextWithPricing({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  Map<String, SupplierPrice>? prices,
}) {
  if (prices == null || prices.isEmpty) {
    return buildVedomostText(project: project, room: room, stamp: stamp);
  }
  final base = buildVedomostText(project: project, room: room, stamp: stamp);
  final buf = StringBuffer()..writeln(base)..writeln('')..writeln(_sectionBanner('Цены'));
  var total = 0.0;
  if (room.finishIncludeCeiling) {
    final ceiling = calculateRoomMaterials(room, project);
    for (final e in sortedMaterialEntries(ceiling)) {
      final (sku, _) = _priceCols(e.key, prices);
      final p = prices[e.key];
      if (p == null || p.unitPriceClient <= 0) {
        buf.writeln(
          _formatVedomostLine(
            e.key,
            '${e.value} шт — цена не задана',
            sku.isNotEmpty ? 'SKU $sku' : '',
          ),
        );
        continue;
      }
      final line = e.value * p.unitPriceClient;
      total += line;
      buf.writeln(
        _formatVedomostLine(
          e.key,
          '${e.value} шт × ${p.unitPriceClient.toStringAsFixed(2)} = ${line.toStringAsFixed(2)}',
          sku.isNotEmpty ? 'SKU $sku' : '',
        ),
      );
    }
    if (total > 0) buf.writeln('Итого потолок · ${total.toStringAsFixed(2)}');
  }
  var finishTotal = 0.0;
  for (final f in buildFinishVedomostLines(room, project: project)) {
    final qty = _parseFinishQty(f);
    if (qty == null) continue;
    if (f.isLinkedMaterial) {
      final p = prices[f.linkedItemKey];
      if (p == null || p.unitPriceClient <= 0) continue;
      final line = qty * p.unitPriceClient;
      finishTotal += line;
      final sku = p.supplierSku.trim();
      buf.writeln(
        _formatVedomostLine(
          '${f.section}: ${f.name}',
          '${f.quantity} ${f.unit} × ${p.unitPriceClient}',
          sku.isNotEmpty ? 'SKU $sku' : '',
        ),
      );
      continue;
    }
    final key = _finishPriceKey(f);
    if (key == null) continue;
    final p = resolveFinishSupplierPrice(sectionKey: key, prices: prices);
    if (p == null || p.unitPriceClient <= 0) continue;
    final line = qty * p.unitPriceClient;
    finishTotal += line;
    final sku = p.supplierSku.trim();
    buf.writeln(
      _formatVedomostLine(
        '${f.section}: ${f.name}',
        '${f.quantity} ${f.unit} × ${p.unitPriceClient}',
        sku.isNotEmpty ? 'SKU $sku' : '',
      ),
    );
  }
  if (finishTotal > 0) {
    buf.writeln('Итого отделка · ${finishTotal.toStringAsFixed(2)}');
  }
  return buf.toString();
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String buildVedomostCsv({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  Map<String, SupplierPrice>? prices,
}) {
  final finish = buildFinishVedomostLines(room, project: project);
  final withPrice = prices != null && prices.isNotEmpty;
  final rows = <List<String>>[
    ['Объект', stamp.objectName.isEmpty ? project.name : stamp.objectName],
    ['Помещение', room.name],
    ['Дата', _date(stamp.issueDate)],
    if (stamp.customer.isNotEmpty) ['Заказчик', stamp.customer],
    if (stamp.executor.isNotEmpty) ['Исполнитель', stamp.executor],
    [],
    if (withPrice)
      ['Раздел', 'Наименование', 'SKU', 'Ед.', 'Кол-во', 'Цена', 'Сумма']
    else
      ['Раздел', 'Наименование', 'Ед.', 'Кол-во'],
  ];
  void addRow(String section, String name, String unit, String qty, {String sku = '', String price = '', String sum = ''}) {
    if (withPrice) {
      rows.add([section, name, sku, unit, qty, price, sum]);
    } else {
      rows.add([section, name, unit, qty]);
    }
  }

  if (room.finishIncludeCeiling) {
    final ceiling = calculateRoomMaterials(room, project);
    final purchase = ceilingPurchaseCount(room);
    addRow('Потолок', 'Плиты/кассеты (закупка)', 'шт', '$purchase');
    for (final e in sortedMaterialEntries(ceiling)) {
      if (withPrice) {
        final (sku, _) = _priceCols(e.key, prices);
        final p = prices![e.key];
        final unit = p?.unitPriceClient ?? 0;
        final sum = unit > 0 ? (e.value * unit).toStringAsFixed(2) : '';
        addRow(
          'Потолок',
          e.key,
          'шт',
          '${e.value}',
          sku: sku,
          price: unit > 0 ? unit.toStringAsFixed(2) : '',
          sum: sum,
        );
      } else {
        addRow('Потолок', e.key, 'шт', '${e.value}');
      }
    }
  }

  final ordered = List<FinishVedomostLine>.from(finish)
    ..sort((a, b) {
      final ai = _vedomostSectionOrder.indexOf(a.section);
      final bi = _vedomostSectionOrder.indexOf(b.section);
      final ao = ai < 0 ? 99 : ai;
      final bo = bi < 0 ? 99 : bi;
      if (ao != bo) return ao.compareTo(bo);
      return a.name.compareTo(b.name);
    });
  for (final f in ordered) {
    if (f.section == 'Потолок' && f.name.contains('закупка')) continue;
    if (withPrice) {
      final (sku, priceCol) = _finishPriceCols(f, prices);
      final qty = _parseFinishQty(f);
      double unit = 0;
      if (f.isLinkedMaterial) {
        unit = prices![f.linkedItemKey]?.unitPriceClient ?? 0;
      } else {
        final priceKey = _finishPriceKey(f);
        final p = priceKey != null
            ? resolveFinishSupplierPrice(sectionKey: priceKey, prices: prices)
            : null;
        unit = p?.unitPriceClient ?? 0;
      }
      final sum = unit > 0 && qty != null ? (qty * unit).toStringAsFixed(2) : '';
      addRow(
        f.section,
        f.name,
        f.unit,
        f.quantity,
        sku: sku,
        price: unit > 0
            ? (priceCol.isNotEmpty ? priceCol : unit.toStringAsFixed(2))
            : '',
        sum: sum,
      );
    } else {
      addRow(f.section, f.name, f.unit, f.quantity);
    }
  }
  return rows.map(_csvRow).join('\n');
}

String buildProjectVedomostCsv({
  required Project project,
  required DocumentationStamp stamp,
}) {
  final finish = aggregateFinishVedomostLines(project);
  final ceilingBom = aggregateCeilingComponentLines(project);
  final rows = <List<String>>[
    ['Объект', stamp.objectName.isEmpty ? project.name : stamp.objectName],
    ['Помещение', 'Все помещения'],
    ['Дата', _date(stamp.issueDate)],
    [],
    ['Раздел', 'Наименование', 'Ед.', 'Кол-во'],
  ];
  for (final f in ceilingBom) {
    rows.add([f.section, f.name, f.unit, f.quantity]);
  }
  for (final f in finish.where((x) => x.section == 'Потолок')) {
    if (f.name.contains('закупка')) continue;
    if (ceilingBom.any((c) => c.name == f.name)) continue;
    rows.add([f.section, f.name, f.unit, f.quantity]);
  }
  final ordered = finish.where((f) => f.section != 'Потолок').toList()
    ..sort((a, b) {
      final ai = _vedomostSectionOrder.indexOf(a.section);
      final bi = _vedomostSectionOrder.indexOf(b.section);
      final ao = ai < 0 ? 99 : ai;
      final bo = bi < 0 ? 99 : bi;
      if (ao != bo) return ao.compareTo(bo);
      return a.name.compareTo(b.name);
    });
  for (final f in ordered) {
    rows.add([f.section, f.name, f.unit, f.quantity]);
  }
  return rows.map(_csvRow).join('\n');
}

String _csvRow(List<String> cells) =>
    cells.map((c) => '"${c.replaceAll('"', '""')}"').join(',');

/// UTF-8 BOM prefix so Excel opens Cyrillic CSV correctly on Windows.
String buildVedomostExcelCsv({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  Map<String, SupplierPrice>? prices,
}) {
  return '\uFEFF${buildVedomostCsv(project: project, room: room, stamp: stamp, prices: prices)}';
}

Uint8List _xlsxFromCsvText(String csvText, {String emptyTitle = 'Ведомость'}) {
  final lines = csvText.split('\n').where((l) => l.trim().isNotEmpty);
  final rows = <List<String>>[];
  for (final line in lines) {
    if (line.startsWith('"')) {
      rows.add(_parseCsvLine(line));
    } else if (!line.contains(',')) {
      rows.add([line]);
    }
  }
  if (rows.isEmpty) rows.add([emptyTitle]);
  return buildSimpleXlsx(sheetName: 'Vedomost', rows: rows);
}

Uint8List buildVedomostXlsx({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  Map<String, SupplierPrice>? prices,
}) {
  return _xlsxFromCsvText(
    buildVedomostCsv(
      project: project,
      room: room,
      stamp: stamp,
      prices: prices,
    ),
  );
}

Uint8List buildProjectVedomostXlsx({
  required Project project,
  required DocumentationStamp stamp,
}) {
  return _xlsxFromCsvText(
    buildProjectVedomostCsv(project: project, stamp: stamp),
    emptyTitle: 'Ведомость объекта',
  );
}

List<String> _parseCsvLine(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch == ',' && !inQuotes) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString());
  return out;
}

String buildVedomostFromTemplate({
  required String templateJson,
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
}) {
  final template = jsonDecode(templateJson) as Map<String, dynamic>;
  final combined = buildCombinedMaterialsSummary(room, project);
  final object = stamp.objectName.isEmpty ? project.name : stamp.objectName;
  final vars = <String, String>{
    'object': object,
    'room': room.name,
    'date': _date(stamp.issueDate),
    'customer': stamp.customer,
    'address': stamp.address,
    'executor': stamp.executor,
  };

  String sub(String s) {
    var out = s;
    for (final e in vars.entries) {
      out = out.replaceAll('{{${e.key}}}', e.value);
    }
    return out;
  }

  final buf = StringBuffer();
  final title = template['title'] as String? ?? 'Ведомость материалов · отделка';
  buf.writeln(sub(title));

  final headerRows = template['header_rows'] as List? ?? [];
  for (final row in headerRows) {
    if (row is! List || row.length < 2) continue;
    buf.writeln('${sub(row[0].toString())}: ${sub(row[1].toString())}');
  }
  buf.writeln('');

  final columns = (template['table_columns'] as List?)?.map((e) => e.toString()).toList() ??
      ['№', 'Наименование', 'Ед.', 'Кол-во'];
  buf.writeln(columns.join(' | '));

  final rowTpl = (template['row_template'] as List?)?.map((e) => e.toString()).toList() ??
      ['{{index}}', '{{name}}', 'шт', '{{qty}}'];
  var i = 1;
  final sortedKeys = combined.keys.toList()..sort(compareMaterialLineKeys);
  for (final key in sortedKeys) {
    final qty = combined[key]!;
    final rowVars = {...vars, 'index': '$i', 'name': key, 'qty': qty};
    final cells = rowTpl.map((cell) {
      var c = cell;
      for (final v in rowVars.entries) {
        c = c.replaceAll('{{${v.key}}}', v.value);
      }
      return c;
    });
    buf.writeln(cells.join(' | '));
    i++;
  }
  return buf.toString();
}

Future<Uint8List> buildProjectVedomostPdf({
  required Project project,
  required DocumentationStamp stamp,
}) async {
  final text = buildProjectVedomostText(project: project, stamp: stamp);
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: '');
  final pdf = await PdfFonts.newDocument();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Text('Ведомость объекта', style: PdfFonts.titleStyle(fontSize: 13)),
        pw.SizedBox(height: 6),
        pw.Text(
          stampFilled.objectName.isEmpty ? project.name : stampFilled.objectName,
          style: PdfFonts.text(fontSize: 9),
        ),
        pw.SizedBox(height: 10),
        ...text.split('\n').map(
              (line) => pw.Text(
                line.isEmpty ? ' ' : line,
                style: PdfFonts.text(fontSize: 9),
              ),
            ),
      ],
    ),
  );
  return pdf.save();
}

Future<Uint8List> buildVedomostPdf({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  String? templateJson,
  Map<String, SupplierPrice>? prices,
}) async {
  final text = templateJson != null
      ? buildVedomostFromTemplate(
          templateJson: templateJson,
          project: project,
          room: room,
          stamp: stamp,
        )
      : buildVedomostTextWithPricing(
          project: project,
          room: room,
          stamp: stamp,
          prices: prices,
        );

  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: room.name);
  final qrPayload = buildDocumentQrPayload(
    docType: 'vedomost',
    projectName: project.name,
    roomName: room.name,
    issuedAt: stampFilled.issueDate,
    documentNumber: stampFilled.documentNumber,
    projectId: project.id,
    roomId: room.id,
  );
  final pdf = await PdfFonts.newDocument();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Text(
          'Ведомость материалов',
          style: PdfFonts.titleStyle(fontSize: 13),
        ),
        pw.SizedBox(height: 6),
        pw.Text('${stampFilled.objectName} / ${room.name}', style: PdfFonts.text(fontSize: 9)),
        pw.SizedBox(height: 10),
        ...text.split('\n').map(
              (line) => pw.Text(
                line.isEmpty ? ' ' : line,
                style: PdfFonts.text(fontSize: 9),
              ),
            ),
        pw.SizedBox(height: 8),
        documentQrFooter(payload: qrPayload),
      ],
    ),
  );
  return pdf.save();
}
