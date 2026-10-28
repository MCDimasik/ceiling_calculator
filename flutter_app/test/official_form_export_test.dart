import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ceiling_calculator/domain/contract_document_model.dart';
import 'package:ceiling_calculator/domain/documentation_model.dart';
import 'package:ceiling_calculator/domain/models.dart';
import 'package:ceiling_calculator/domain/money_format.dart';
import 'package:ceiling_calculator/domain/official_form_export.dart';
import 'package:ceiling_calculator/domain/partner_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final rectWalls = [
    [0.0, 0.0, 400.0, 0.0],
    [400.0, 0.0, 400.0, 300.0],
    [400.0, 300.0, 0.0, 300.0],
    [0.0, 300.0, 0.0, 0.0],
  ];

  test('buildWorkLines single mode one KS-style line', () {
    final room = Room(name: '101', walls: rectWalls);
    final settings = ContractDocumentSettings(
      lineMode: ProposalLineMode.single,
      unifiedPricePerM2: 700,
      scopeNote: 'Дом 1',
    );
    final lines = buildWorkLines(settings: settings, rooms: [room]);
    expect(lines.length, 1);
    expect(lines.first.name, contains('Выполнение работ по отделке'));
    expect(lines.first.name, contains('Дом 1'));
    // floor 12 + walls ~37.8 + ceiling 12
    expect(lines.first.quantity, greaterThan(30));
  });

  test('buildWorkLines single keeps KS title; qty follows include flags', () {
    final room = Room(
      name: '101',
      walls: rectWalls,
      finishIncludeFloor: false,
      finishIncludeWalls: false,
      finishIncludeCeiling: true,
    );
    final lines = buildWorkLines(
      settings: ContractDocumentSettings(unifiedPricePerM2: 700),
      rooms: [room],
    );
    expect(lines.length, 1);
    expect(lines.first.name, 'Выполнение работ по отделке помещений');
    expect(lines.first.quantity, closeTo(12, 0.1));
  });

  test('buildWorkLines by room splits lines per room and scope', () {
    final rooms = [
      Room(id: 1, name: 'A', walls: rectWalls, finishIncludeWalls: false),
      Room(id: 2, name: 'B', walls: rectWalls, finishIncludeWalls: false),
    ];
    final settings = ContractDocumentSettings(
      lineMode: ProposalLineMode.byRoom,
      unifiedPricePerM2: 700,
    );
    final lines = buildWorkLines(settings: settings, rooms: rooms);
    // 2 rooms × (floor + ceiling) = 4
    expect(lines.length, 4);
    expect(lines.any((l) => l.name.contains('A')), isTrue);
    expect(lines.any((l) => l.name.contains('B')), isTrue);
    expect(lines.every((l) => l.lineKey.isNotEmpty), isTrue);
  });

  test('formatRub uses space thousands separator', () {
    expect(formatRub(1000000), '1 000 000 ₽');
    expect(formatRub(10000), '10 000 ₽');
    expect(formatMoney(16900.5, fractionDigits: 2), '16 900,50');
  });

  test('byRoom KS-2 expands merges on data rows', () async {
    final blankData = await rootBundle.load(
      'assets/document_templates/avangard.ks2.blank.xlsx',
    );
    final blankBytes = blankData.buffer.asUint8List();
    final project = Project(name: 'Тест byRoom');
    var doc = applyPartnerDefaults(ProjectDocumentation(), fillAvangardCustomer: true);
    doc.contractDocs = ContractDocumentSettings(
      lineMode: ProposalLineMode.byRoom,
      unifiedPricePerM2: 800,
    );
    final rooms = [
      Room(id: 1, name: 'A', walls: rectWalls, finishIncludeWalls: false),
      Room(id: 2, name: 'B', walls: rectWalls, finishIncludeWalls: false),
    ];
    expect(ks2DataRowCount(settings: doc.contractDocs, rooms: rooms), 4);

    final bytes = await buildOfficialKs2Xlsx(
      project: project,
      doc: doc,
      stamp: doc.stamp,
      rooms: rooms,
      actNumber: 2,
      issueDate: DateTime(2025, 5, 29),
      periodFrom: DateTime(2025, 5, 21),
      periodTo: DateTime(2025, 5, 29),
      blankBytes: blankBytes,
    );
    final zip = ZipDecoder().decodeBytes(bytes);
    final sheet = utf8.decode(
      zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    // Cloned data rows 32..35 should exist.
    expect(sheet.contains('<row r="33"'), isTrue);
    expect(sheet.contains('<row r="35"'), isTrue);
    // Template-row merges should be cloned (e.g. F32:N32 → F33:N33 …).
    expect(sheet.contains('F33:N33') || sheet.contains('ref="F33:N33"'), isTrue);
  });

  test('official KS2 xlsx produces bytes', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final project = Project(name: 'Тест');
    var doc = ProjectDocumentation();
    doc = applyPartnerDefaults(doc, fillAvangardCustomer: true);
    doc.contract.contractNumber = '08/04-2025';
    doc.contract.buildSite = 'ул. Пархоменко, 1';
    final room = Room(name: '101', walls: rectWalls);
    final bytes = await buildOfficialKs2Xlsx(
      project: project,
      doc: doc,
      stamp: doc.stamp,
      rooms: [room],
      actNumber: 1,
      issueDate: DateTime(2025, 5, 29),
      periodFrom: DateTime(2025, 5, 21),
      periodTo: DateTime(2025, 5, 29),
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(2)), 'PK');
  });

  test('commercial proposal xlsx', () {
    final project = Project(name: 'Тест');
    final doc = applyPartnerDefaults(ProjectDocumentation());
    final room = Room(name: '101', walls: rectWalls);
    final bytes = buildCommercialProposalXlsx(
      project: project,
      doc: doc,
      stamp: doc.stamp,
      rooms: [room],
    );
    expect(bytes.length, greaterThan(500));
  });

  test('partner profile fills executor', () {
    final stamp = PartnerProfile.defaultGusev.applyToStamp(DocumentationStamp());
    expect(stamp.executor, contains('Гусев'));
  });

  test('Avangard customer splits name and address', () {
    final doc = applyPartnerDefaults(
      ProjectDocumentation(),
      fillAvangardCustomer: true,
    );
    expect(doc.stamp.customer, 'ООО «ГК Авангард»');
    expect(doc.stamp.address, contains('Менделеева'));
    expect(doc.stamp.customer.contains('400074'), isFalse);
  });

  test('legacy Avangard line normalizes into address', () {
    final stamp = DocumentationStamp(
      customer: PartnerProfile.avangardCustomerLegacyLine,
    );
    normalizeStampCustomerAddress(stamp);
    expect(stamp.customer, 'ООО «ГК Авангард»');
    expect(stamp.address, PartnerProfile.avangardCustomer.address);
  });

  test('universal customer/address split by postal index', () {
    final stamp = DocumentationStamp(
      customer: 'ООО «Ромашка», 344000, г. Ростов-на-Дону, ул. Ленина, 1',
    );
    normalizeStampCustomerAddress(stamp);
    expect(stamp.customer, 'ООО «Ромашка»');
    expect(stamp.address, startsWith('344000'));
  });

  test('simple xlsx zip has non-zero uncompressed sizes', () {
    final bytes = buildCommercialProposalXlsx(
      project: Project(name: 'Тест'),
      doc: ProjectDocumentation(),
      stamp: DocumentationStamp(customer: 'ООО «А»', address: 'ул. 1'),
      rooms: [Room(name: '101', walls: rectWalls)],
    );
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4b);
    expect(bytes.length, greaterThan(500));
    // Local file header uncompressed size at offset 22 (uint32) must be > 0.
    // Find first local header after PK\x03\x04.
    expect(bytes[2], 0x03);
    expect(bytes[3], 0x04);
    final usize = bytes[22] | (bytes[23] << 8) | (bytes[24] << 16) | (bytes[25] << 24);
    expect(usize, greaterThan(0), reason: 'Excel rejects XLSX with usize=0 (CRC errors)');
  });

  test('filled KS-2 does not swallow neighboring cells', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final blankData = await rootBundle.load(
      'assets/document_templates/avangard.ks2.blank.xlsx',
    );
    final blankBytes = blankData.buffer.asUint8List();
    final blankZip = ZipDecoder().decodeBytes(blankBytes);
    final blankSheet = utf8.decode(
      blankZip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    final blankCells = RegExp(r'<c ').allMatches(blankSheet).length;

    final project = Project(name: 'Пархоменко 24');
    var doc = applyPartnerDefaults(ProjectDocumentation(), fillAvangardCustomer: true);
    doc.contractDocs = ContractDocumentSettings(
      lineMode: ProposalLineMode.single,
      workTitle: 'Выполнение работ по отделке помещений',
      unifiedPricePerM2: 700,
    );
    final bytes = await buildOfficialKs2Xlsx(
      project: project,
      doc: doc,
      stamp: doc.stamp,
      rooms: [Room(name: '101', walls: rectWalls)],
      actNumber: 5,
      issueDate: DateTime(2025, 5, 29),
      periodFrom: DateTime(2025, 5, 21),
      periodTo: DateTime(2025, 5, 29),
      blankBytes: blankBytes,
    );
    final fillZip = ZipDecoder().decodeBytes(bytes);
    final fillSheet = utf8.decode(
      fillZip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    final fillCells = RegExp(r'<c ').allMatches(fillSheet).length;
    // May replace/add a few value cells, but must not delete dozens of neighbors.
    expect(fillCells, greaterThanOrEqualTo(blankCells - 2));
    expect(fillSheet.contains('t="inlineStr"'), isFalse);
    final ss = utf8.decode(
      fillZip.findFile('xl/sharedStrings.xml')!.content as List<int>,
    );
    expect(ss.contains('<si>'), isTrue);
  });

  test('filled KS-2 blank uses sharedStrings only (no inlineStr)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final project = Project(name: 'Пархоменко 24');
    var doc = ProjectDocumentation();
    doc = applyPartnerDefaults(doc, fillAvangardCustomer: true);
    doc.contract.contractNumber = '08/04-2025';
    doc.contract.buildSite = 'ул. Пархоменко, 24';
    doc.contractDocs = ContractDocumentSettings(
      lineMode: ProposalLineMode.single,
      workTitle: 'Выполнение работ по отделке помещений',
      unifiedPricePerM2: 700,
    );
    final room = Room(name: '101', walls: rectWalls);
    final bytes = await buildOfficialKs2Xlsx(
      project: project,
      doc: doc,
      stamp: doc.stamp,
      rooms: [room],
      actNumber: 3,
      issueDate: DateTime(2025, 5, 29),
      periodFrom: DateTime(2025, 5, 21),
      periodTo: DateTime(2025, 5, 29),
    );
    expect(bytes.length, greaterThan(2000));

    final zip = ZipDecoder().decodeBytes(bytes);
    final sheetFile = zip.findFile('xl/worksheets/sheet1.xml');
    final ssFile = zip.findFile('xl/sharedStrings.xml');
    expect(sheetFile, isNotNull);
    expect(ssFile, isNotNull);
    final sheet = utf8.decode(sheetFile!.content as List<int>);
    final ss = utf8.decode(ssFile!.content as List<int>);
    expect(sheet.contains('t="inlineStr"'), isFalse,
        reason: 'inlineStr breaks Excel when blank uses sharedStrings');
    expect(sheet.contains('t="s"'), isTrue);
    expect(ss.contains('Выполнение работ по отделке помещений'), isTrue);
    expect(ss.contains('Пархоменко'), isTrue);
  });
}
