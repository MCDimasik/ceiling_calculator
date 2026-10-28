import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/documentation_model.dart';
import 'package:ceiling_calculator/domain/office_doc_reader.dart';
import 'package:ceiling_calculator/domain/project_doc_import.dart';
import 'package:ceiling_calculator/domain/project_price_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parseProjectDocument extracts stamp fields from text', () {
    const text = '''
Договор № 12/2025 от 01.03.2025
Заказчик: ООО «Строй»
Исполнитель: ИП Иванов
Объект: Школа №5
Адрес: г. Москва, ул. Ленина 1
Смета № С-44
ИНН: 7701234567
''';
    final parsed = parseProjectDocument(text);
    expect(parsed.customer, contains('Строй'));
    expect(parsed.executor, contains('Иванов'));
    expect(parsed.objectName, contains('Школа'));
    expect(parsed.contractNumber, isNotEmpty);
    expect(parsed.estimateNumber, contains('С-44'));
    expect(parsed.customerInn, '7701234567');
  });

  test('parseProjectDocument reads CSV prices', () {
    const csv = '''match_key;наименование;ед;цена
finish_floor;Пол;м²;850.50
finish_wall;Стены;м²;620
''';
    final parsed = parseProjectDocument(csv, filename: 'rates.csv');
    expect(parsed.prices.length, 2);
    expect(parsed.prices.first.matchKey, 'finish_floor');
    expect(parsed.prices.first.unitPrice, 850.50);
  });

  test('parsePriceTableRows reads smeta-style Excel header', () {
    final rows = [
      ['Заказчик', 'ООО Тест'],
      ['№ п/п', 'Обоснование', 'Наименование', 'Ед.изм.', 'Кол-во', 'Расценка', 'Сумма'],
      ['1', '01-01', 'Устройство пола', 'м²', '10', '850', '8500'],
      ['2', '02-01', 'Облицовка стен', 'м²', '20', '620', '12400'],
      ['', '', 'Итого', '', '', '', '20900'],
    ];
    final prices = parsePriceTableRows(rows);
    expect(prices.length, 2);
    expect(prices.first.name, contains('пола'));
    expect(prices.first.unitPrice, 850);
  });

  test('parseProjectDocumentBytes reads XLSX template', () async {
    final bytes = buildProjectPriceImportTemplateXlsx();
    final parsed = await parseProjectDocumentBytes(bytes, 'template.xlsx');
    expect(parsed.warning, isEmpty);
    expect(parsed.prices.length, greaterThanOrEqualTo(4));
    expect(parsed.prices.any((p) => p.matchKey == 'finish_floor'), isTrue);
  });

  test('parseProjectDocumentBytes reads DOCX contract text', () async {
    final bytes = buildSimpleDocx([
      'Договор № 99/2026',
      'Заказчик: ООО Альфа',
      'Исполнитель: ООО Бета',
      'Объект: ТЦ Мега',
    ]);
    final parsed = await parseProjectDocumentBytes(bytes, 'contract.docx');
    expect(parsed.customer, contains('Альфа'));
    expect(parsed.executor, contains('Бета'));
    expect(parsed.objectName, contains('Мега'));
  });

  test('legacy xls shows warning', () async {
    final parsed = await parseProjectDocumentBytes(Uint8List.fromList([0, 1, 2]), 'old.xls');
    expect(parsed.warning, contains('.xlsx'));
  });

  test('applyParsedProjectDocument infers enabledWorkScopes from keys', () {
    final doc = ProjectDocumentation();
    final parsed = ParsedProjectDocument(
      prices: [
        ProjectPriceLine(matchKey: 'finish_floor', name: 'Пол', unitPrice: 100),
        ProjectPriceLine(matchKey: 'finish_wall', name: 'Стены', unitPrice: 200),
      ],
    );
    final out = applyParsedProjectDocument(doc, parsed);
    expect(out.enabledWorkScopes, ['floor', 'walls']);
  });

  test('applyParsedProjectDocument merges prices by key', () {
    final doc = ProjectDocumentation(
      ks2Prices: [
        ProjectPriceLine(matchKey: 'finish_floor', name: 'Пол', unitPrice: 100),
      ],
    );
    final parsed = ParsedProjectDocument(
      customer: 'ACME',
      prices: [
        ProjectPriceLine(matchKey: 'finish_floor', name: 'Пол', unitPrice: 900),
        ProjectPriceLine(matchKey: 'finish_wall', name: 'Стены', unitPrice: 500),
      ],
    );
    final out = applyParsedProjectDocument(doc, parsed);
    expect(out.stamp.customer, 'ACME');
    expect(out.ks2Prices.length, 2);
    expect(
      out.ks2Prices.firstWhere((p) => p.matchKey == 'finish_floor').unitPrice,
      900,
    );
  });

  test('resolveKs2UnitPrice prefers project rates', () {
    final price = resolveKs2UnitPrice(
      name: 'Плитка пола',
      section: 'Пол',
      projectPrices: [
        ProjectPriceLine(matchKey: 'finish_floor', name: 'Пол', unitPrice: 777),
      ],
      supplierPrices: null,
    );
    expect(price, 777);
  });

  test('ProjectDocumentation serializes contract and prices', () {
    final doc = ProjectDocumentation(
      contract: ProjectContractInfo(contractNumber: 'D-1', vatRatePercent: 20),
      ks2Prices: [
        ProjectPriceLine(matchKey: 'purchase', name: 'Закупка', unitPrice: 200),
      ],
      useProjectPricesOnly: true,
    );
    final raw = doc.toJson();
    final back = ProjectDocumentation.fromJson(raw);
    expect(back.contract.contractNumber, 'D-1');
    expect(back.ks2Prices.single.unitPrice, 200);
    expect(back.useProjectPricesOnly, isTrue);
  });
}
