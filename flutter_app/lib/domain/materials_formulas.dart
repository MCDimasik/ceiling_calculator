/// Human-readable material formulas (parity with layout + materials_spec).
String materialsFormulasText({
  required String ceilingLabel,
  required double areaM2,
  required double perimeterM,
}) {
  final calcType = switch (ceilingLabel) {
    'GL' => 'grilyato_gl',
    'Грильято' => 'grilyato_classic',
    _ => 'armstrong',
  };
  final lines = <String>[
    'Формулы расчета:',
    'Уголок = ceil(P/3) = ceil(${perimeterM.toStringAsFixed(2)}/3)',
    'S = ${areaM2.toStringAsFixed(2)} м²',
    '',
  ];
  if (calcType == 'armstrong' || calcType == 'grilyato_gl') {
    lines.addAll([
      'Каркас (если нет раскладки направляющих):',
      'Направляющая 3600 = ceil((S * 0.84) / 3.6)',
      'Направляющая 1200 = ceil((S * 1.68) / 1.2)',
      'Направляющая 600 = ceil((S * 0.85) / 0.6)',
      'Подвес = Направляющая 3600 * 4',
      'При раскладке направляющих — количества берутся с чертежа.',
    ]);
  } else {
    lines.addAll([
      'Каркас как у Армстронга, несущие 2400 (если нет раскладки):',
      'Направляющая 2400 = ceil((S * 0.84) / 2.4)',
      'Направляющая 1200 = ceil((S * 1.68) / 1.2)',
      'Направляющая 600 = ceil((S * 0.85) / 0.6)',
      'Соединитель = Направляющая 2400',
      'Подвес = Направляющая 2400 * 3',
      'При раскладке направляющих — количества берутся с чертежа.',
    ]);
  }
  if (calcType == 'grilyato_gl' || calcType == 'grilyato_classic') {
    lines.addAll([
      '',
      'Кассеты (закупка): N = max(ceil(S/0.36), упаковка раскладки)',
      '  · площадь: как у поставщиков (10×10 м → 278)',
      '  · раскладка: целые + ceil(сумма площадей резов / 0.36), крошки <3 см игнор',
      'Решётка (папа/мама по 600 мм):',
      '50x50  → Папа = Мама = N * 11',
      '75x75  → Папа = Мама = N * 7',
      '100x100 → Папа = Мама = N * 5',
    ]);
    if (calcType == 'grilyato_gl') {
      lines.add('L-профиль / Заглушки = N * 4');
    }
  } else {
    lines.addAll([
      '',
      'Плиты (закупка): N = max(ceil(S/0.36), упаковка раскладки)',
      'На экране раскладки по-прежнему видны целые и резаные ячейки.',
    ]);
  }
  lines.addAll([
    '',
    'Светильники:',
    'Армстронг: −1 плита на светильник',
    'Грильято: −k папа/мама на светильник (50→11, 75→7, 100→5)',
  ]);
  return lines.join('\n');
}
