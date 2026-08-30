/// Full catalog (parity with Python `material_catalog.py`).
class CatalogEntry {
  const CatalogEntry(this.category, this.itemKey, this.displayName, this.calcMatchKey);
  final String category;
  final String itemKey;
  final String displayName;
  final String calcMatchKey;
}

const catalogEntries = <CatalogEntry>[
  CatalogEntry('Плиты Армстронг', 'armstrong_tile', 'Плита Армстронг', 'Плиты/кассеты (Армстронг)'),
  CatalogEntry('Плиты Армстронг', 'armstrong_baikal', 'Плита Армстронг Байкал', 'Плиты/кассеты (Армстронг)'),
  CatalogEntry('Плиты Армстронг', 'armstrong_retail', 'Плита Армстронг Retail', 'Плиты/кассеты (Армстронг)'),
  CatalogEntry('Плиты Армстронг', 'armstrong_metal', 'Плита Армстронг металлическая', 'Плиты/кассеты (Армстронг)'),
  CatalogEntry('Плиты Армстронг', 'armstrong_metal_perf', 'Плита Армстронг металл. перфорированная', 'Плиты/кассеты (Армстронг)'),
  CatalogEntry('Плиты Армстронг', 'armstrong_oregon', 'Плита Армстронг Oregon', 'Плиты/кассеты (Армстронг)'),
  CatalogEntry('Кассеты / решётки', 'cassette_grilyato', 'Кассета Грильято', 'Плиты/кассеты (Грильято)'),
  CatalogEntry('Кассеты / решётки', 'cassette_grilyato_white', 'Кассета Грильято белая', 'Плиты/кассеты (Грильято)'),
  CatalogEntry('Кассеты / решётки', 'cassette_grilyato_black', 'Кассета Грильято чёрная', 'Плиты/кассеты (Грильято)'),
  CatalogEntry('Кассеты / решётки', 'cassette_gl', 'Кассета GL', 'Плиты/кассеты (GL)'),
  CatalogEntry('Кассеты / решётки', 'cassette_gl_white', 'Кассета GL белая', 'Плиты/кассеты (GL)'),
  CatalogEntry('Кассеты / решётки', 'cassette_gl_black', 'Кассета GL чёрная', 'Плиты/кассеты (GL)'),
  CatalogEntry('Светильники', 'light_fixture_led', 'Светильник LED 600×600', 'Светильники'),
  CatalogEntry('Подвесы', 'susp_05', 'Подвес 0,5 м', 'Подвес (0,5)'),
  CatalogEntry('Подвесы', 'susp_10', 'Подвес 1 м', 'Подвес (1)'),
  CatalogEntry('Подвесы', 'susp_15', 'Подвес 1,5 м', 'Подвес (1,5)'),
  CatalogEntry('Направляющие', 'guide_3600', 'Направляющая 3600', 'Направляющая 3600'),
  CatalogEntry('Направляющие', 'guide_1200', 'Направляющая 1200', 'Направляющая 1200'),
  CatalogEntry('Направляющие', 'guide_600', 'Направляющая 600', 'Направляющая 600'),
  CatalogEntry('Направляющие', 'guide_2400', 'Направляющая 2400', 'Направляющая 2400'),
  CatalogEntry('Профили', 'profile_papa_50', 'Профиль Папа 50×50', 'Профиль Папа (50x50)'),
  CatalogEntry('Профили', 'profile_mama_50', 'Профиль Мама 50×50', 'Профиль Мама (50x50)'),
  CatalogEntry('Профили', 'profile_papa_75', 'Профиль Папа 75×75', 'Профиль Папа (75x75)'),
  CatalogEntry('Профили', 'profile_mama_75', 'Профиль Мама 75×75', 'Профиль Мама (75x75)'),
  CatalogEntry('Профили', 'profile_papa_100', 'Профиль Папа 100×100', 'Профиль Папа (100x100)'),
  CatalogEntry('Профили', 'profile_mama_100', 'Профиль Мама 100×100', 'Профиль Мама (100x100)'),
  CatalogEntry('Прочее', 'corner', 'Уголок 3 м', 'Уголок'),
  CatalogEntry('Прочее', 'connector', 'Соединитель', 'Соединитель'),
  CatalogEntry('Прочее', 'stopper_50', 'Заглушки 50×50', 'Заглушки (50x50)'),
  CatalogEntry('Прочее', 'stopper_75', 'Заглушки 75×75', 'Заглушки (75x75)'),
  CatalogEntry('Прочее', 'stopper_100', 'Заглушки 100×100', 'Заглушки (100x100)'),
];

CatalogEntry? catalogByItemKey(String key) {
  for (final e in catalogEntries) {
    if (e.itemKey == key) return e;
  }
  return null;
}

int defaultUnitsPerPack(String itemKey) {
  if (itemKey.startsWith('armstrong_')) return 20;
  return 1;
}

String defaultReceiptUnit(String itemKey) => 'piece';

/// Groups by calc_match_key for supplier UI.
List<({String category, String calcMatchKey, String title, List<CatalogEntry> variants})>
    catalogProductGroups() {
  final ordered = <({String category, String calcMatchKey, String title, List<CatalogEntry> variants})>[];
  final index = <String, int>{};
  for (final e in catalogEntries) {
    final gk = '${e.category}|${e.calcMatchKey}';
    if (!index.containsKey(gk)) {
      index[gk] = ordered.length;
      ordered.add((
        category: e.category,
        calcMatchKey: e.calcMatchKey,
        title: e.displayName,
        variants: [e],
      ));
    } else {
      final i = index[gk]!;
      final g = ordered[i];
      ordered[i] = (
        category: g.category,
        calcMatchKey: g.calcMatchKey,
        title: g.title,
        variants: [...g.variants, e],
      );
    }
  }
  return ordered
      .map((g) => (
            category: g.category,
            calcMatchKey: g.calcMatchKey,
            title: g.variants.length == 1
                ? g.variants.first.displayName
                : g.variants.first.displayName.split(' ').take(2).join(' '),
            variants: g.variants,
          ))
      .toList();
}
