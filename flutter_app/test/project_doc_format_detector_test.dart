import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/project_doc_format_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('detectColumnMap finds smeta headers', () {
    final rows = [
      ['Заказчик', 'ООО Тест'],
      ['№', 'Обоснование', 'Наименование работ', 'Ед.', 'Расценка', 'Сумма'],
      ['1', '01-01', 'Пол', 'м²', '850', '8500'],
    ];
    final map = detectColumnMap(rows);
    expect(map.headerRowIndex, 1);
    expect(map.colName, 2);
    expect(map.colPrice, 4);
    final prices = parsePriceRowsWithColumnMap(rows, map);
    expect(prices.length, 1);
    expect(prices.first.unitPrice, 850);
  });

  test('detectBestDocFormatProfile picks smeta profile', () async {
    final profiles = await loadDocImportFormatProfiles();
    expect(profiles, isNotEmpty);
    final text = 'Наименование работ и затрат\nРасценка\nЕд. изм.';
    final rows = [
      ['Наименование', 'Ед.', 'Расценка'],
      ['Пол', 'м²', '100'],
    ];
    final (profile, score) = detectBestDocFormatProfile(
      text: text,
      rows: rows,
      profiles: profiles,
    );
    expect(profile, isNotNull);
    expect(score, greaterThan(0));
  });
}
