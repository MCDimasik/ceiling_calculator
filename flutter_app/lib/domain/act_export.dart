import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'contract_document_model.dart';
import 'cost_calculator.dart';
import 'documentation_model.dart';
import 'document_qr.dart';
import 'finish_layer_pricing.dart';
import 'finish_vedomost.dart';
import 'ks2_act_service.dart';
import 'ks2_work_scope.dart';
import 'materials_calculator.dart';
import 'models.dart';
import 'pdf_fonts.dart';
import 'pdf_stamp_block.dart';
import 'project_materials.dart';
import 'project_price_resolver.dart';
import 'room_documentation_status.dart';
import 'work_rates_catalog.dart';
import 'xlsx_export.dart';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _actNumberLabel(int? actNumber) =>
    actNumber != null && actNumber > 0 ? actNumber.toString() : '___';

/// Formal text act for hidden works inspection (simplified Russian form).
String buildHiddenWorksActText({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  required RoomDocumentationChecklist checklist,
  int? actNumber,
}) {
  final summary = roomDocumentationSummary(room, project, checklist: checklist);
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: room.name);
  final finish = buildFinishVedomostLines(room);

  final buf = StringBuffer()
    ..writeln('АКТ ОСМОТРА СКРЫТЫХ РАБОТ № ${_actNumberLabel(actNumber)}')
    ..writeln('по комплексу отделки помещения')
    ..writeln('')
    ..writeln('Объект: ${stampFilled.objectName}')
    ..writeln('Помещение: ${room.name}')
    ..writeln('Дата: ${_date(stampFilled.issueDate)}');
  if (stampFilled.customer.isNotEmpty) buf.writeln('Заказчик: ${stampFilled.customer}');
  if (stampFilled.address.isNotEmpty) buf.writeln('Адрес: ${stampFilled.address}');
  if (stampFilled.executor.isNotEmpty) buf.writeln('Исполнитель: ${stampFilled.executor}');
  if (checklist.assignee.isNotEmpty) buf.writeln('Бригада: ${checklist.assignee}');
  buf
    ..writeln('')
    ..writeln('Комиссия установила, что выполнены следующие скрытые работы:')
    ..writeln('');

  for (final st in summary.steps.where((s) => s.step.phase == DocumentationPhase.hiddenWorks)) {
    if (!st.applies) {
      buf.writeln('  — ${st.step.title}: не предусмотрено (${st.hint})');
      continue;
    }
    final note = checklist.stepNotes[st.step.id];
    final mark = st.done ? '✓' : '○';
    buf.writeln('  $mark ${st.step.title} · ${st.hint}${note != null && note.isNotEmpty ? ' · $note' : ''}');
  }

  buf
    ..writeln('')
    ..writeln('Объёмы комплекса отделки (факт):');

  for (final f in finish) {
    buf.writeln('  [${f.section}] ${f.name}: ${f.quantity} ${f.unit}');
  }

  if (checklist.notes.isNotEmpty) {
    buf.writeln('');
    buf.writeln('Примечания: ${checklist.notes}');
  }

  buf
    ..writeln('')
    ..writeln('Статус документации: проект ${summary.designDone}/${summary.designTotal} · '
        'скрытые ${summary.hiddenWorksDone}/${summary.hiddenWorksTotal}')
    ..writeln('')
    ..writeln('Представитель заказчика: _________________ / _________________')
    ..writeln('Представитель исполнителя: _________________ / _________________');

  return buf.toString();
}

String _sku(String key, Map<String, SupplierPrice>? prices) {
  if (prices == null) return '';
  return prices[key]?.supplierSku ?? '';
}

/// KS-2 style materials / works table with section codes.
String buildKs2MaterialsText({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  Map<String, SupplierPrice>? prices,
}) {
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: room.name);
  final ceiling = calculateRoomMaterials(room, project);
  final finish = buildFinishVedomostLines(room);
  final purchase = ceilingPurchaseCount(room);
  final area = room.hasLayout ? MaterialsCalculator.roomAreaM2(room.walls) : 0.0;
  final withSku = prices != null && prices.isNotEmpty;

  final buf = StringBuffer()
    ..writeln('ФОРМА КС-2 (упрощённая) · комплекс отделки')
    ..writeln('Объект: ${stampFilled.objectName}')
    ..writeln('Помещение: ${room.name}')
    ..writeln('Дата: ${_date(stampFilled.issueDate)}')
    ..writeln('')
    ..writeln(withSku
        ? 'Код | SKU | Наименование | Ед. | Кол-во | Раздел'
        : 'Код | Наименование | Ед. | Кол-во | Раздел')
    ..writeln(withSku
        ? '----|-----|--------------|-----|--------|-------'
        : '----|--------------|-----|--------|-------');

  var code = 1;
  void row(String codeStr, String sku, String name, String unit, String qty, String section) {
    if (withSku) {
      buf.writeln('$codeStr | ${sku.isEmpty ? '—' : sku} | $name | $unit | $qty | $section');
    } else {
      buf.writeln('$codeStr | $name | $unit | $qty | $section');
    }
    code++;
  }

  if (room.hasLayout) {
    row('01', '', 'Площадь пола', 'м²', area.toStringAsFixed(2), 'Пол');
    row('02', '', 'Площадь потолка', 'м²', area.toStringAsFixed(2), 'Потолок');
  } else {
    buf.writeln('Примечание: нет закрытого чертежа — площади и материалы не рассчитаны.');
    buf.writeln('');
  }

  for (final e in sortedMaterialEntries(ceiling)) {
    row('10', _sku(e.key, prices), e.key, 'шт', '${e.value}', 'Потолок');
  }
  row('11', _sku('purchase', prices), 'Плиты/кассеты (закупка)', 'шт', '$purchase', 'Потолок');

  for (final f in finish) {
    // Skip area lines already emitted above / as «Площадь» under Пол/Потолок.
    if (f.name == 'Площадь' || f.name.startsWith('Площадь ')) continue;
    if (f.section == 'Потолок' && f.name.contains('закупка')) continue;
    final sku = f.isLinkedMaterial
        ? _sku(f.linkedItemKey!, prices)
        : _sku(
            switch (f.section) {
              'Пол' => 'finish_floor',
              'Стены' => 'finish_wall',
              'Потолок' => 'finish_ceiling',
              _ => '',
            },
            prices,
          );
    row('20', sku, f.name, f.unit, f.quantity, f.section);
  }

  buf.writeln('');
  buf.writeln('Примечание: расценки и итоги заполняются в учётной системе.');
  buf.writeln('Подписи: заказчик _____________  исполнитель _____________');
  return buf.toString();
}

/// Default bundled GOST-style KS-2 template asset path.
const defaultKs2TemplateAsset = 'assets/document_templates/_example.ks2.template.json';

/// Default bundled KS-3 template asset path.
const defaultKs3TemplateAsset = 'assets/document_templates/_example.ks3.template.json';

/// Default bundled hidden-works act template asset path.
const defaultActHiddenTemplateAsset =
    'assets/document_templates/_example.act_hidden.template.json';

String _subTemplate(String s, Map<String, String> vars) {
  var out = s;
  for (final e in vars.entries) {
    out = out.replaceAll('{{${e.key}}}', e.value);
  }
  return out;
}

List<Map<String, String>> ks2TableRows({
  required Project project,
  required Room room,
  WorkScope? scope,
}) {
  final ceiling = calculateRoomMaterials(room, project);
  final finish = buildFinishVedomostLines(room);
  final purchase = ceilingPurchaseCount(room);
  final area = room.hasLayout ? MaterialsCalculator.roomAreaM2(room.walls) : 0.0;
  final rows = <Map<String, String>>[];
  if (room.hasLayout) {
    rows.addAll([
      {
        'name': 'Площадь пола',
        'unit': 'м²',
        'qty': area.toStringAsFixed(2),
        'section': 'Пол',
      },
      {
        'name': 'Площадь потолка',
        'unit': 'м²',
        'qty': area.toStringAsFixed(2),
        'section': 'Потолок',
      },
    ]);
  }
  for (final e in sortedMaterialEntries(ceiling)) {
    rows.add({'name': e.key, 'unit': 'шт', 'qty': '${e.value}', 'section': 'Потолок'});
  }
  rows.add({
    'name': 'Плиты/кассеты (закупка)',
    'unit': 'шт',
    'qty': '$purchase',
    'section': 'Потолок',
  });
  for (final f in finish) {
    if (f.name == 'Площадь' || f.name.startsWith('Площадь ')) continue;
    if (f.section == 'Потолок' && f.name.contains('закупка')) continue;
    rows.add({
      'name': f.name,
      'unit': f.unit,
      'qty': f.quantity,
      'section': f.section,
      if (f.isLinkedMaterial) 'linked_item_key': f.linkedItemKey!,
    });
  }
  if (scope == null) return rows;
  return rows.where((r) => ks2RowMatchesScope(r, scope)).toList();
}

/// Scoped rows for multiple rooms (project-level KS-2).
List<Map<String, String>> ks2ProjectScopedRows({
  required Project project,
  required List<Room> rooms,
  required List<WorkScope> scopes,
}) {
  final out = <Map<String, String>>[];
  for (final room in rooms) {
    for (final scope in scopes) {
      for (final row in ks2TableRows(project: project, room: room, scope: scope)) {
        out.add({...row, 'room': room.name});
      }
    }
  }
  return out;
}

double ks2ScopedTotal({
  required Project project,
  required Room room,
  required WorkScope scope,
  Map<String, SupplierPrice>? prices,
  List<ProjectPriceLine>? projectPrices,
  bool projectPricesOnly = false,
}) =>
    ks2ProjectScopedTotal(
      project: project,
      rooms: [room],
      scopes: [scope],
      prices: prices,
      projectPrices: projectPrices,
      projectPricesOnly: projectPricesOnly,
    );

double ks2ProjectScopedTotal({
  required Project project,
  required List<Room> rooms,
  required List<WorkScope> scopes,
  Map<String, SupplierPrice>? prices,
  List<ProjectPriceLine>? projectPrices,
  bool projectPricesOnly = false,
}) {
  final doc = ProjectDocumentation.fromJson(project.documentationJson);
  // Same economics as «Смета»: room×scope work lines (not vedomost materials).
  final contractTotal = _contractDocsScopedTotal(
    settings: doc.contractDocs,
    rooms: rooms,
    floors: project.floors,
    scopes: scopes,
    catalog: WorkRatesCatalogStore.peek(),
    supplierPrices: prices,
  );
  if (contractTotal > 0) return contractTotal;

  // Fallback: vedomost qty × project/catalog/supplier rates (legacy).
  final effectiveProjectPrices = projectPrices ?? doc.ks2Prices;
  var total = 0.0;
  for (final room in rooms) {
    for (final scope in scopes) {
      for (final data in ks2TableRows(project: project, room: room, scope: scope)) {
        final qtyNum = double.tryParse(data['qty']!.replaceAll(',', '.')) ?? 0;
        final unitPrice = resolveKs2UnitPrice(
          name: data['name']!,
          section: data['section']!,
          projectPrices: effectiveProjectPrices,
          supplierPrices: prices,
          projectPricesOnly: projectPricesOnly || doc.useProjectPricesOnly,
          linkedItemKey: data['linked_item_key'],
        );
        if (unitPrice != null) total += unitPrice * qtyNum;
      }
    }
  }
  return total;
}

/// Sum of scoped contract work lines for the given rooms / work scopes.
double _contractDocsScopedTotal({
  required ContractDocumentSettings settings,
  required List<Room> rooms,
  required List<ProjectFloor> floors,
  required List<WorkScope> scopes,
  List<WorkRateCategory>? catalog,
  Map<String, SupplierPrice>? supplierPrices,
}) {
  if (rooms.isEmpty || scopes.isEmpty) return 0;
  final want = <String>{
    for (final s in scopes)
      switch (s) {
        WorkScope.floor => 'floor',
        WorkScope.walls => 'walls',
        WorkScope.ceiling => 'ceiling',
      },
  };
  final lines = buildScopedContractWorkLines(
    settings: settings,
    rooms: rooms,
    floors: floors,
    scopeIds: want,
    catalog: catalog,
    supplierPrices: supplierPrices,
  );
  return lines.fold<double>(0, (s, l) => s + l.lineSum);
}

/// Table rows for KS-2 acts: work lines as in smeta (not material vedomost).
List<Map<String, String>> ks2ContractWorkRows({
  required Project project,
  required List<Room> rooms,
  required List<WorkScope> scopes,
  Map<String, SupplierPrice>? prices,
}) {
  final doc = ProjectDocumentation.fromJson(project.documentationJson);
  final want = <String>{
    for (final s in scopes)
      switch (s) {
        WorkScope.floor => 'floor',
        WorkScope.walls => 'walls',
        WorkScope.ceiling => 'ceiling',
      },
  };
  final lines = buildScopedContractWorkLines(
    settings: doc.contractDocs,
    rooms: rooms,
    floors: project.floors,
    scopeIds: want,
    catalog: WorkRatesCatalogStore.peek(),
    supplierPrices: prices,
  );
  final sectionRu = {
    'floor': 'Пол',
    'walls': 'Стены',
    'ceiling': 'Потолок',
  };
  return [
    for (var i = 0; i < lines.length; i++)
      {
        'index': '${i + 1}',
        'name': lines[i].name,
        'unit': lines[i].unit,
        'qty': lines[i].quantity.toStringAsFixed(2),
        'section': sectionRu[lines[i].section] ?? lines[i].section,
        'section_id': lines[i].section,
        'price': lines[i].unitPrice.toStringAsFixed(2),
        'sum': lines[i].lineSum.toStringAsFixed(2),
        'room': '', // name already includes room in by-room mode
      },
  ];
}

String buildKs2FromTemplate({
  required String templateJson,
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  Map<String, SupplierPrice>? prices,
  List<ProjectPriceLine>? projectPrices,
  bool projectPricesOnly = false,
}) {
  final template = jsonDecode(templateJson) as Map<String, dynamic>;
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: room.name);
  final vars = <String, String>{
    'object': stampFilled.objectName,
    'room': room.name,
    'date': _date(stampFilled.issueDate),
    'customer': stampFilled.customer,
    'address': stampFilled.address,
    'executor': stampFilled.executor,
    'total_sum': '—',
  };

  final doc = ProjectDocumentation.fromJson(project.documentationJson);
  vars['contract_number'] = doc.contract.contractNumber;
  vars['estimate_number'] = doc.contract.estimateNumber;
  vars['customer_inn'] = doc.contract.customerInn;

  final buf = StringBuffer();
  buf.writeln(_subTemplate(template['title'] as String? ?? 'КС-2', vars));
  final subtitle = template['subtitle'] as String?;
  if (subtitle != null && subtitle.isNotEmpty) {
    buf.writeln(_subTemplate(subtitle, vars));
  }
  buf.writeln('');

  for (final row in template['header_rows'] as List? ?? []) {
    if (row is! List || row.length < 2) continue;
    buf.writeln('${_subTemplate(row[0].toString(), vars)}: ${_subTemplate(row[1].toString(), vars)}');
  }
  buf.writeln('');

  final columns = (template['table_columns'] as List?)?.map((e) => e.toString()).toList() ??
      ['№', 'Наименование', 'Ед.', 'Кол-во', 'Раздел'];
  buf.writeln(columns.join(' | '));
  buf.writeln(List.filled(columns.length, '---').join(' | '));

  final rowTpl = (template['row_template'] as List?)?.map((e) => e.toString()).toList() ??
      ['{{index}}', '{{name}}', '{{unit}}', '{{qty}}', '{{section}}'];
  var i = 1;
  var totalSum = 0.0;
  final effectiveProjectPrices = projectPrices ?? doc.ks2Prices;
  for (final data in ks2TableRows(project: project, room: room)) {
    final qtyNum = double.tryParse(data['qty']!.replaceAll(',', '.')) ?? 0;
    final unitPrice = resolveKs2UnitPrice(
      name: data['name']!,
      section: data['section']!,
      projectPrices: effectiveProjectPrices,
      supplierPrices: prices,
      projectPricesOnly: projectPricesOnly || doc.useProjectPricesOnly,
      linkedItemKey: data['linked_item_key'],
    );
    final lineSum = unitPrice != null ? unitPrice * qtyNum : null;
    if (lineSum != null) totalSum += lineSum;
    final rowVars = {
      ...vars,
      'index': '$i',
      ...data,
      'price': unitPrice != null ? unitPrice.toStringAsFixed(2) : '—',
      'sum': lineSum != null ? lineSum.toStringAsFixed(2) : '—',
    };
    buf.writeln(rowTpl.map((c) => _subTemplate(c, rowVars)).join(' | '));
    i++;
  }
  if (totalSum > 0) vars['total_sum'] = totalSum.toStringAsFixed(2);

  buf.writeln('');
  for (final line in template['footer_lines'] as List? ?? []) {
    buf.writeln(_subTemplate(line.toString(), vars));
  }
  return buf.toString();
}

/// Project-level KS-2 for [scopes], aggregated from [rooms].
String buildProjectKs2FromTemplate({
  required String templateJson,
  required Project project,
  required List<Room> rooms,
  required List<WorkScope> scopes,
  required DocumentationStamp stamp,
  required int actNumber,
  Map<String, SupplierPrice>? prices,
  List<ProjectPriceLine>? projectPrices,
  bool projectPricesOnly = false,
}) {
  final template = jsonDecode(templateJson) as Map<String, dynamic>;
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: '');
  final roomList = rooms.map((r) => r.name).join(', ');
  final scopeLabel = scopes.map((s) => s.labelRu).join(' + ');
  final vars = <String, String>{
    'object': stampFilled.objectName,
    'room': roomList.isEmpty ? '—' : roomList,
    'date': _date(stampFilled.issueDate),
    'customer': stampFilled.customer,
    'address': stampFilled.address,
    'executor': stampFilled.executor,
    'scope': scopeLabel,
    'act_number': actNumber.toString(),
    'total_sum': '—',
  };

  final doc = ProjectDocumentation.fromJson(project.documentationJson);
  vars['contract_number'] = doc.contract.contractNumber;
  vars['estimate_number'] = doc.contract.estimateNumber;
  vars['customer_inn'] = doc.contract.customerInn;

  final buf = StringBuffer();
  final title = template['title'] as String? ?? 'КС-2';
  buf.writeln(_subTemplate(title, vars));
  buf.writeln('Вид работ: $scopeLabel · Акт № $actNumber');
  final subtitle = template['subtitle'] as String?;
  if (subtitle != null && subtitle.isNotEmpty) {
    buf.writeln(_subTemplate(subtitle, vars));
  }
  buf.writeln('Помещения: $roomList');
  buf.writeln('');

  for (final row in template['header_rows'] as List? ?? []) {
    if (row is! List || row.length < 2) continue;
    final key = row[0].toString();
    if (key.contains('Помещение')) continue;
    buf.writeln('${_subTemplate(key, vars)}: ${_subTemplate(row[1].toString(), vars)}');
  }
  buf.writeln('');

  final columns = (template['table_columns'] as List?)?.map((e) => e.toString()).toList() ??
      ['№', 'Наименование', 'Ед.', 'Кол-во', 'Раздел'];
  final withRoom = ['Помещение', ...columns];
  buf.writeln(withRoom.join(' | '));
  buf.writeln(List.filled(withRoom.length, '---').join(' | '));

  final rowTpl = (template['row_template'] as List?)?.map((e) => e.toString()).toList() ??
      ['{{index}}', '{{name}}', '{{unit}}', '{{qty}}', '{{section}}'];
  final projectRowTpl = ['{{room}}', ...rowTpl];
  var i = 1;
  var totalSum = 0.0;
  for (final data in ks2ContractWorkRows(
    project: project,
    rooms: rooms,
    scopes: scopes,
    prices: prices,
  )) {
    final qtyNum = double.tryParse(data['qty']!.replaceAll(',', '.')) ?? 0;
    final unitPrice = double.tryParse(data['price']!.replaceAll(',', '.'));
    final lineSum = unitPrice != null ? unitPrice * qtyNum : null;
    if (lineSum != null) totalSum += lineSum;
    final rowVars = {
      ...vars,
      'index': '$i',
      ...data,
      'price': unitPrice != null ? unitPrice.toStringAsFixed(2) : '—',
      'sum': lineSum != null ? lineSum.toStringAsFixed(2) : '—',
    };
    buf.writeln(projectRowTpl.map((c) => _subTemplate(c, rowVars)).join(' | '));
    i++;
  }
  if (totalSum > 0) vars['total_sum'] = totalSum.toStringAsFixed(2);

  buf.writeln('');
  for (final line in template['footer_lines'] as List? ?? []) {
    buf.writeln(_subTemplate(line.toString(), vars));
  }
  return buf.toString();
}

String buildKs3FromLedger({
  required String templateJson,
  required Project project,
  required DocumentationStamp stamp,
  required DateTime periodFrom,
  required DateTime periodTo,
  required List<Ks2ActRecord> acts,
}) {
  final template = jsonDecode(templateJson) as Map<String, dynamic>;
  final doc = ProjectDocumentation.fromJson(project.documentationJson);
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: '');
  final vatRate = doc.contract.vatRatePercent;

  String fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  final ledgerRows = buildKs3LedgerRows(
    acts: activeKs2Acts(acts),
    periodFrom: periodFrom,
    periodTo: periodTo,
  );

  final periodTotal = ledgerRows.fold<double>(0, (s, r) => s + r.periodSum);
  final cumulativeTotal = ledgerRows.fold<double>(0, (s, r) => s + r.cumulativeSum);
  final vatAmount = vatRate > 0 ? periodTotal * vatRate / 100 : 0.0;
  final totalWithVat = periodTotal + vatAmount;

  final vars = <String, String>{
    'object': stampFilled.objectName,
    'date': _date(stampFilled.issueDate),
    'customer': stampFilled.customer,
    'address': stampFilled.address,
    'executor': stampFilled.executor,
    'contract_number': doc.contract.contractNumber,
    'estimate_number': doc.contract.estimateNumber,
    'customer_inn': doc.contract.customerInn,
    'period_from': fmtDate(periodFrom),
    'period_to': fmtDate(periodTo),
    'period_sum': periodTotal > 0 ? periodTotal.toStringAsFixed(2) : '—',
    'cumulative_sum': cumulativeTotal > 0 ? cumulativeTotal.toStringAsFixed(2) : '—',
    'vat_rate': vatRate > 0 ? vatRate.toStringAsFixed(0) : '0',
    'vat_sum': vatAmount > 0 ? vatAmount.toStringAsFixed(2) : '—',
    'total_with_vat': totalWithVat > 0 ? totalWithVat.toStringAsFixed(2) : '—',
  };

  final buf = StringBuffer();
  buf.writeln(_subTemplate(template['title'] as String? ?? 'КС-3', vars));
  buf.writeln('Нарастающая справка по закрытым КС-2');
  final subtitle = template['subtitle'] as String?;
  if (subtitle != null && subtitle.isNotEmpty) {
    buf.writeln(_subTemplate(subtitle, vars));
  }
  buf.writeln('');

  for (final row in template['header_rows'] as List? ?? []) {
    if (row is! List || row.length < 2) continue;
    buf.writeln('${_subTemplate(row[0].toString(), vars)}: ${_subTemplate(row[1].toString(), vars)}');
  }
  buf.writeln('');

  final columns = [
    '№ п/п',
    'Вид работ',
    'С начала работ',
    'Ранее закрыто',
    'За период',
    'Помещения',
  ];
  buf.writeln(columns.join(' | '));
  buf.writeln(List.filled(columns.length, '---').join(' | '));

  var i = 1;
  for (final row in ledgerRows) {
    buf.writeln([
      '$i',
      row.scopeLabel,
      row.cumulativeSum.toStringAsFixed(2),
      row.previousSum.toStringAsFixed(2),
      row.periodSum > 0 ? row.periodSum.toStringAsFixed(2) : '—',
      row.roomNames.join(', '),
    ].join(' | '));
    i++;
  }

  buf.writeln('');
  buf.writeln('Итого с начала работ (по реестру КС-2): ${vars['cumulative_sum']}');
  for (final line in template['footer_lines'] as List? ?? []) {
    buf.writeln(_subTemplate(line.toString(), vars));
  }
  return buf.toString();
}
double ks2RoomTotal({
  required Project project,
  required Room room,
  Map<String, SupplierPrice>? prices,
  List<ProjectPriceLine>? projectPrices,
  bool projectPricesOnly = false,
}) {
  final doc = ProjectDocumentation.fromJson(project.documentationJson);
  final effectiveProjectPrices = projectPrices ?? doc.ks2Prices;
  var total = 0.0;
  for (final data in ks2TableRows(project: project, room: room)) {
    final qtyNum = double.tryParse(data['qty']!.replaceAll(',', '.')) ?? 0;
    final unitPrice = resolveKs2UnitPrice(
      name: data['name']!,
      section: data['section']!,
      projectPrices: effectiveProjectPrices,
      supplierPrices: prices,
      projectPricesOnly: projectPricesOnly || doc.useProjectPricesOnly,
      linkedItemKey: data['linked_item_key'],
    );
    if (unitPrice != null) total += unitPrice * qtyNum;
  }
  return total;
}

String buildKs3FromTemplate({
  required String templateJson,
  required Project project,
  required DocumentationStamp stamp,
  required DateTime periodFrom,
  required DateTime periodTo,
  Map<String, SupplierPrice>? prices,
  List<ProjectPriceLine>? projectPrices,
  bool projectPricesOnly = false,
}) {
  final doc = ProjectDocumentation.fromJson(project.documentationJson);
  if (doc.ks2Acts.isNotEmpty) {
    return buildKs3FromLedger(
      templateJson: templateJson,
      project: project,
      stamp: stamp,
      periodFrom: periodFrom,
      periodTo: periodTo,
      acts: doc.ks2Acts,
    );
  }
  final template = jsonDecode(templateJson) as Map<String, dynamic>;
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: '');
  final vatRate = doc.contract.vatRatePercent;

  String fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  final rows = <Map<String, String>>[];
  var periodTotal = 0.0;
  for (final room in project.rooms) {
    if (!room.hasLayout) continue;
    final sum = ks2RoomTotal(
      project: project,
      room: room,
      prices: prices,
      projectPrices: projectPrices,
      projectPricesOnly: projectPricesOnly,
    );
    periodTotal += sum;
    rows.add({
      'room': room.name,
      'sum': sum > 0 ? sum.toStringAsFixed(2) : '—',
    });
  }

  final vatAmount = vatRate > 0 ? periodTotal * vatRate / 100 : 0.0;
  final totalWithVat = periodTotal + vatAmount;

  final vars = <String, String>{
    'object': stampFilled.objectName,
    'date': _date(stampFilled.issueDate),
    'customer': stampFilled.customer,
    'address': stampFilled.address,
    'executor': stampFilled.executor,
    'contract_number': doc.contract.contractNumber,
    'estimate_number': doc.contract.estimateNumber,
    'customer_inn': doc.contract.customerInn,
    'period_from': fmtDate(periodFrom),
    'period_to': fmtDate(periodTo),
    'period_sum': periodTotal > 0 ? periodTotal.toStringAsFixed(2) : '—',
    'vat_rate': vatRate > 0 ? vatRate.toStringAsFixed(0) : '0',
    'vat_sum': vatAmount > 0 ? vatAmount.toStringAsFixed(2) : '—',
    'total_with_vat': totalWithVat > 0 ? totalWithVat.toStringAsFixed(2) : '—',
  };

  final buf = StringBuffer();
  buf.writeln(_subTemplate(template['title'] as String? ?? 'КС-3', vars));
  final subtitle = template['subtitle'] as String?;
  if (subtitle != null && subtitle.isNotEmpty) {
    buf.writeln(_subTemplate(subtitle, vars));
  }
  buf.writeln('');

  for (final row in template['header_rows'] as List? ?? []) {
    if (row is! List || row.length < 2) continue;
    buf.writeln('${_subTemplate(row[0].toString(), vars)}: ${_subTemplate(row[1].toString(), vars)}');
  }
  buf.writeln('');

  final columns = (template['table_columns'] as List?)?.map((e) => e.toString()).toList() ??
      ['№', 'Помещение', 'Сумма'];
  buf.writeln(columns.join(' | '));
  buf.writeln(List.filled(columns.length, '---').join(' | '));

  final rowTpl = (template['row_template'] as List?)?.map((e) => e.toString()).toList() ??
      ['{{index}}', '{{room}}', '{{sum}}'];
  var i = 1;
  for (final data in rows) {
    final rowVars = {...vars, 'index': '$i', ...data};
    buf.writeln(rowTpl.map((c) => _subTemplate(c, rowVars)).join(' | '));
    i++;
  }

  buf.writeln('');
  for (final line in template['footer_lines'] as List? ?? []) {
    buf.writeln(_subTemplate(line.toString(), vars));
  }
  return buf.toString();
}

Future<Uint8List> buildKs3MaterialsPdf({
  required Project project,
  required DocumentationStamp stamp,
  required DateTime periodFrom,
  required DateTime periodTo,
  required String templateJson,
  Map<String, SupplierPrice>? prices,
  List<ProjectPriceLine>? projectPrices,
  bool projectPricesOnly = false,
}) async {
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: '');
  final body = buildKs3FromTemplate(
    templateJson: templateJson,
    project: project,
    stamp: stamp,
    periodFrom: periodFrom,
    periodTo: periodTo,
    prices: prices,
    projectPrices: projectPrices,
    projectPricesOnly: projectPricesOnly,
  );
  String fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  final qrPayload = buildDocumentQrPayload(
    docType: 'ks3',
    projectName: project.name,
    roomName: 'все помещения',
    issuedAt: stampFilled.issueDate,
    documentNumber: '${fmtDate(periodFrom)}-${fmtDate(periodTo)}',
    projectId: project.id,
  );
  return _gostTablePdf(
    title: 'КС-3 · ${project.name}',
    stamp: stampFilled,
    roomName: 'все помещения',
    templateJson: templateJson,
    body: body,
    qrPayload: qrPayload,
  );
}

String buildHiddenWorksActFromTemplate({
  required String templateJson,
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  required RoomDocumentationChecklist checklist,
  int? actNumber,
}) {
  final template = jsonDecode(templateJson) as Map<String, dynamic>;
  final summary = roomDocumentationSummary(room, project, checklist: checklist);
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: room.name);
  final finish = buildFinishVedomostLines(room);
  final vars = <String, String>{
    'object': stampFilled.objectName,
    'room': room.name,
    'date': _date(stampFilled.issueDate),
    'customer': stampFilled.customer,
    'address': stampFilled.address,
    'executor': stampFilled.executor,
    'assignee': checklist.assignee,
    'act_number': _actNumberLabel(actNumber),
  };

  final buf = StringBuffer();
  buf.writeln(_subTemplate(template['title'] as String? ?? 'Акт скрытых работ', vars));
  final subtitle = template['subtitle'] as String?;
  if (subtitle != null && subtitle.isNotEmpty) {
    buf.writeln(_subTemplate(subtitle, vars));
  }
  buf.writeln('');

  for (final row in template['header_rows'] as List? ?? []) {
    if (row is! List || row.length < 2) continue;
    buf.writeln('${_subTemplate(row[0].toString(), vars)}: ${_subTemplate(row[1].toString(), vars)}');
  }
  buf.writeln('');

  for (final section in template['sections'] as List? ?? []) {
    if (section is! Map) continue;
    final heading = section['heading'] as String?;
    if (heading != null && heading.isNotEmpty) {
      buf.writeln(_subTemplate(heading, vars));
      buf.writeln('');
    }
    final rowTpl = (section['row_template'] as List?)?.map((e) => e.toString()).toList();
    if (rowTpl == null) continue;

    if (heading?.contains('скрытые') == true) {
      for (final st in summary.steps.where((s) => s.step.phase == DocumentationPhase.hiddenWorks)) {
        if (!st.applies) {
          buf.writeln('— | ${st.step.title} | не предусмотрено');
          continue;
        }
        final note = checklist.stepNotes[st.step.id];
        final hint = '${st.hint}${note != null && note.isNotEmpty ? ' · $note' : ''}';
        final rowVars = {
          ...vars,
          'mark': st.done ? '✓' : '○',
          'title': st.step.title,
          'hint': hint,
        };
        buf.writeln(rowTpl.map((c) => _subTemplate(c, rowVars)).join(' | '));
      }
    } else {
      for (final f in finish) {
        final rowVars = {
          ...vars,
          'section': f.section,
          'name': f.name,
          'qty': f.quantity,
          'unit': f.unit,
        };
        buf.writeln(rowTpl.map((c) => _subTemplate(c, rowVars)).join(' | '));
      }
    }
    buf.writeln('');
  }

  if (checklist.notes.isNotEmpty) {
    buf.writeln('Примечания: ${checklist.notes}');
    buf.writeln('');
  }

  for (final line in template['footer_lines'] as List? ?? []) {
    buf.writeln(_subTemplate(line.toString(), vars));
  }
  return buf.toString();
}

Future<Uint8List> buildHiddenWorksActPdf({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  required RoomDocumentationChecklist checklist,
  int? actNumber,
  String? templateJson,
}) async {
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: room.name);
  if (templateJson != null) {
    return _gostTablePdf(
      title: 'Акт скрытых работ № ${_actNumberLabel(actNumber)} · ${room.name}',
      stamp: stampFilled,
      roomName: room.name,
      templateJson: templateJson,
      body: buildHiddenWorksActFromTemplate(
        templateJson: templateJson,
        project: project,
        room: room,
        stamp: stamp,
        checklist: checklist,
        actNumber: actNumber,
      ),
    );
  }
  final text = buildHiddenWorksActText(
    project: project,
    room: room,
    stamp: stamp,
    checklist: checklist,
    actNumber: actNumber,
  );
  return _textDocumentPdf(
    title: 'Акт скрытых работ № ${_actNumberLabel(actNumber)} · ${room.name}',
    body: text,
    stamp: stamp.withDefaults(projectName: project.name, roomName: room.name),
    roomName: room.name,
  );
}

Future<Uint8List> buildProjectKs2MaterialsPdf({
  required Project project,
  required List<Room> rooms,
  required List<WorkScope> scopes,
  required DocumentationStamp stamp,
  required int actNumber,
  Map<String, SupplierPrice>? prices,
  String? templateJson,
  int? projectId,
}) async {
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: '');
  final tpl = templateJson ?? '';
  final scopeLabel = scopes.map((s) => s.labelRu).join(' + ');
  final body = buildProjectKs2FromTemplate(
    templateJson: tpl,
    project: project,
    rooms: rooms,
    scopes: scopes,
    stamp: stamp,
    actNumber: actNumber,
    prices: prices,
  );
  final qrPayload = buildDocumentQrPayload(
    docType: 'ks2',
    projectName: project.name,
    roomName: rooms.map((r) => r.name).join(', '),
    issuedAt: stamp.issueDate,
    documentNumber: actNumber.toString(),
    projectId: projectId ?? project.id,
  );
  return _gostTablePdf(
    title: 'КС-2 № $actNumber · $scopeLabel · ${project.name}',
    stamp: stampFilled,
    roomName: rooms.map((r) => r.name).join(', '),
    templateJson: tpl,
    body: body,
    qrPayload: qrPayload,
  );
}

Future<Uint8List> buildKs2MaterialsPdf({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  Map<String, SupplierPrice>? prices,
  String? templateJson,
}) async {
  final stampFilled = stamp.withDefaults(projectName: project.name, roomName: room.name);
  final qrPayload = buildDocumentQrPayload(
    docType: 'ks2',
    projectName: project.name,
    roomName: room.name,
    issuedAt: stampFilled.issueDate,
    projectId: project.id,
    roomId: room.id,
  );
  if (templateJson != null) {
    return _gostTablePdf(
      title: 'КС-2 · ${room.name}',
      stamp: stampFilled,
      roomName: room.name,
      templateJson: templateJson,
      body: buildKs2FromTemplate(
        templateJson: templateJson,
        project: project,
        room: room,
        stamp: stamp,
        prices: prices,
      ),
      qrPayload: qrPayload,
    );
  }
  final text = buildKs2MaterialsText(
    project: project,
    room: room,
    stamp: stamp,
    prices: prices,
  );
  return _textDocumentPdf(
    title: 'КС-2 · ${room.name}',
    body: text,
    stamp: stamp.withDefaults(projectName: project.name, roomName: room.name),
    roomName: room.name,
    qrPayload: qrPayload,
  );
}

Uint8List buildProjectKs2Xlsx({
  required Project project,
  required List<Room> rooms,
  required List<WorkScope> scopes,
  required DocumentationStamp stamp,
  required int actNumber,
  Map<String, SupplierPrice>? prices,
}) {
  final doc = ProjectDocumentation.fromJson(project.documentationJson);
  final roomList = rooms.map((r) => r.name).join(', ');
  final scopeLabel = scopes.map((s) => s.labelRu).join(' + ');
  final rows = <List<String>>[
    ['КС-2 № $actNumber', stamp.objectName.isEmpty ? project.name : stamp.objectName, scopeLabel],
    ['Помещения', roomList, ''],
    ['Дата', _date(stamp.issueDate), ''],
    if (doc.contract.contractNumber.isNotEmpty) ['Договор', doc.contract.contractNumber, ''],
    [],
    ['№', 'Помещение', 'SKU', 'Наименование', 'Ед.', 'Кол-во', 'Цена', 'Сумма', 'Раздел'],
  ];

  var i = 1;
  var total = 0.0;
  for (final data in ks2ContractWorkRows(
    project: project,
    rooms: rooms,
    scopes: scopes,
    prices: prices,
  )) {
    final qtyNum = double.tryParse(data['qty']!.replaceAll(',', '.')) ?? 0;
    final unitPrice = double.tryParse(data['price']!.replaceAll(',', '.'));
    final lineSum = unitPrice != null ? unitPrice * qtyNum : null;
    if (lineSum != null) total += lineSum;
    final sku = _skuForContractSection(data['section_id'], prices);
    rows.add([
      '$i',
      data['room'] ?? '',
      sku.isEmpty ? '—' : sku,
      data['name']!,
      data['unit'] ?? '',
      data['qty']!,
      unitPrice?.toStringAsFixed(2) ?? '—',
      lineSum?.toStringAsFixed(2) ?? '—',
      data['section']!,
    ]);
    i++;
  }
  rows.add([]);
  rows.add(['Итого', total > 0 ? total.toStringAsFixed(2) : '—', '', '', '', '', '', '', '']);
  return buildSimpleXlsx(sheetName: 'KS-2', rows: rows);
}

String _skuForContractSection(
  String? sectionId,
  Map<String, SupplierPrice>? prices,
) {
  if (prices == null || sectionId == null || sectionId.isEmpty) return '';
  final key = switch (sectionId) {
    'floor' => 'finish_floor',
    'walls' => 'finish_wall',
    'ceiling' => 'finish_ceiling',
    _ => '',
  };
  if (key.isEmpty) return '';
  return resolveFinishSku(sectionKey: key, prices: prices);
}

String _skuForKs2Row(Map<String, String> data, Map<String, SupplierPrice>? prices) {
  if (prices == null) return '';
  final section = data['section'] ?? '';
  final key = ks2SectionPriceKey(section);
  if (key != null) return _sku(key, prices);
  return '';
}

Uint8List buildKs2Xlsx({
  required Project project,
  required Room room,
  required DocumentationStamp stamp,
  Map<String, SupplierPrice>? prices,
  String? templateJson,
}) {
  final doc = ProjectDocumentation.fromJson(project.documentationJson);
  final rows = <List<String>>[
    ['КС-2', stamp.objectName.isEmpty ? project.name : stamp.objectName, room.name],
    ['Дата', _date(stamp.issueDate), ''],
    if (doc.contract.contractNumber.isNotEmpty)
      ['Договор', doc.contract.contractNumber, ''],
    [],
    ['№', 'SKU', 'Наименование', 'Ед.', 'Кол-во', 'Цена', 'Сумма', 'Раздел'],
  ];

  var i = 1;
  var total = 0.0;
  for (final data in ks2TableRows(project: project, room: room)) {
    final qtyNum = double.tryParse(data['qty']!.replaceAll(',', '.')) ?? 0;
    final unitPrice = resolveKs2UnitPrice(
      name: data['name']!,
      section: data['section']!,
      projectPrices: doc.ks2Prices,
      supplierPrices: prices,
      projectPricesOnly: doc.useProjectPricesOnly,
      linkedItemKey: data['linked_item_key'],
    );
    final lineSum = unitPrice != null ? unitPrice * qtyNum : null;
    if (lineSum != null) total += lineSum;
    final linked = data['linked_item_key'];
    final sku = (linked != null && linked.isNotEmpty)
        ? _sku(linked, prices)
        : _skuForKs2Row(data, prices);
    rows.add([
      '$i',
      sku.isEmpty ? '—' : sku,
      data['name']!,
      data['unit'] ?? '',
      data['qty']!,
      unitPrice?.toStringAsFixed(2) ?? '—',
      lineSum?.toStringAsFixed(2) ?? '—',
      data['section']!,
    ]);
    i++;
  }
  rows.add([]);
  rows.add(['Итого', total > 0 ? total.toStringAsFixed(2) : '—', '', '', '', '', '']);

  return buildSimpleXlsx(sheetName: 'KS-2', rows: rows);
}

Future<Uint8List> _textDocumentPdf({
  required String title,
  required String body,
  required DocumentationStamp stamp,
  required String roomName,
  String? qrPayload,
}) async {
  final pdf = await PdfFonts.newDocument();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) {
        final widgets = <pw.Widget>[
          pw.Text(title, style: PdfFonts.titleStyle()),
          pw.SizedBox(height: 6),
          pdfGostTitleBlock(stamp: stamp, roomName: roomName),
          pw.SizedBox(height: 12),
          ...body.split('\n').map(
                (line) => pw.Text(
                  line.isEmpty ? ' ' : line,
                  style: PdfFonts.text(fontSize: 10),
                ),
              ),
        ];
        if (qrPayload != null && qrPayload.isNotEmpty) {
          widgets.add(pw.SizedBox(height: 8));
          widgets.add(documentQrFooter(payload: qrPayload));
        }
        return widgets;
      },
    ),
  );
  return pdf.save();
}

Future<Uint8List> _gostTablePdf({
  required String title,
  required DocumentationStamp stamp,
  required String roomName,
  required String templateJson,
  required String body,
  String? qrPayload,
}) async {
  final template = jsonDecode(templateJson) as Map<String, dynamic>;
  final columns = (template['table_columns'] as List?)?.map((e) => e.toString()).toList();
  final pdf = await PdfFonts.newDocument();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) {
        final widgets = <pw.Widget>[
          pw.Text(title, style: PdfFonts.titleStyle()),
          pw.SizedBox(height: 6),
          pdfGostTitleBlock(stamp: stamp, roomName: roomName),
          pw.SizedBox(height: 10),
        ];

        void finish() {
          if (qrPayload != null && qrPayload.isNotEmpty) {
            widgets.add(pw.SizedBox(height: 8));
            widgets.add(documentQrFooter(payload: qrPayload));
          }
        }

        if (columns != null && columns.isNotEmpty) {
          final lines = body.split('\n');
          final tableStart = lines.indexWhere((l) => l.contains(' | ') && l.contains('---'));
          if (tableStart > 0) {
            for (var i = 0; i < tableStart - 1; i++) {
              if (lines[i].trim().isEmpty) {
                widgets.add(pw.SizedBox(height: 4));
              } else {
                widgets.add(pw.Text(lines[i], style: PdfFonts.text(fontSize: 10)));
              }
            }
            final header = lines[tableStart - 1].split(' | ');
            final dataRows = <List<String>>[];
            for (var i = tableStart + 1; i < lines.length; i++) {
              final line = lines[i].trim();
              if (line.isEmpty || line.startsWith('Итого') || line.startsWith('Заказчик')) break;
              if (line.contains(' | ')) dataRows.add(line.split(' | '));
            }
            widgets.add(
              pw.Table.fromTextArray(
                headers: header,
                data: dataRows,
                headerStyle: PdfFonts.text(fontSize: 9),
                cellStyle: PdfFonts.text(fontSize: 9),
                border: pw.TableBorder.all(width: 0.5),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              ),
            );
            widgets.add(pw.SizedBox(height: 10));
            for (var i = tableStart + 1 + dataRows.length; i < lines.length; i++) {
              if (lines[i].trim().isEmpty) continue;
              widgets.add(pw.Text(lines[i], style: PdfFonts.text(fontSize: 9)));
            }
            finish();
            return widgets;
          }
        }

        widgets.addAll(
          body.split('\n').map(
                (line) => pw.Text(
                  line.isEmpty ? ' ' : line,
                  style: PdfFonts.text(fontSize: 10),
                ),
              ),
        );
        finish();
        return widgets;
      },
    ),
  );
  return pdf.save();
}
