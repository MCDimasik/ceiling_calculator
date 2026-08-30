import 'material_catalog.dart';

class AliasHit {
  const AliasHit({
    required this.itemKey,
    this.receiptUnit,
    this.unitsPerPack,
    this.productName,
  });
  final String itemKey;
  final String? receiptUnit;
  final double? unitsPerPack;
  final String? productName;
}

class _Rule {
  const _Rule({
    required this.priority,
    required this.itemKey,
    this.allContains = const [],
    this.anyContains = const [],
    this.noneContains = const [],
    this.regex = const [],
    this.receiptUnit,
    this.unitsPerPack,
  });
  final int priority;
  final String itemKey;
  final List<String> allContains;
  final List<String> anyContains;
  final List<String> noneContains;
  final List<String> regex;
  final String? receiptUnit;
  final double? unitsPerPack;
}

const _rules = <_Rule>[
  _Rule(priority: 120, itemKey: 'armstrong_retail', allContains: ['ритейл'], anyContains: ['армстронг', 'плит'], receiptUnit: 'pack', unitsPerPack: 20),
  _Rule(priority: 115, itemKey: 'armstrong_metal_perf', anyContains: ['цесал', 'cesal'], allContains: ['кассет']),
  _Rule(priority: 110, itemKey: 'armstrong_metal_perf', allContains: ['перф'], anyContains: ['плит', 'кассет', 'алюмин']),
  _Rule(priority: 100, itemKey: 'armstrong_baikal', allContains: ['байкал'], anyContains: ['армстронг', 'плит'], receiptUnit: 'pack', unitsPerPack: 20),
  _Rule(priority: 95, itemKey: 'armstrong_tile', allContains: ['армстронг'], anyContains: ['плит', 'потолочн'], noneContains: ['грильято', 'grilyato', 'профиль', 'направляющ'], receiptUnit: 'pack', unitsPerPack: 20),
  _Rule(priority: 120, itemKey: 'light_fixture_led', anyContains: ['светильник', 'led', '595']),
  _Rule(priority: 110, itemKey: 'susp_05', regex: [r'европодвес.*500', r'500\s*мм', r'подвес.*0[,.]5', r'0[,.]5\s*м']),
  _Rule(priority: 100, itemKey: 'susp_10', regex: [r'подвес.*1\s*м', r'европодвес.*1000'], noneContains: ['1,5', '1.5']),
  _Rule(priority: 100, itemKey: 'susp_15', regex: [r'подвес.*1[,.]5']),
  _Rule(priority: 110, itemKey: 'corner', anyContains: ['уголок', 'l-профиль', 'уголковый']),
  _Rule(priority: 100, itemKey: 'guide_3600', allContains: ['3600'], anyContains: ['направляющ', 'профиль']),
  _Rule(priority: 100, itemKey: 'guide_1200', allContains: ['1200'], anyContains: ['направляющ', 'профиль']),
  _Rule(priority: 100, itemKey: 'guide_600', allContains: ['600'], anyContains: ['направляющ'], noneContains: ['3600', '1200', '2400', 'светильник']),
  _Rule(priority: 100, itemKey: 'guide_2400', allContains: ['2400'], anyContains: ['направляющ', 'профиль']),
  _Rule(priority: 90, itemKey: 'cassette_grilyato', anyContains: ['грильято', 'grilyato'], noneContains: ['профиль', 'папа', 'мама']),
  _Rule(priority: 90, itemKey: 'cassette_gl', anyContains: [' кассета gl', 'gl '], noneContains: ['грильято']),
  _Rule(priority: 85, itemKey: 'connector', anyContains: ['соединител']),
  _Rule(priority: 80, itemKey: 'profile_papa_50', allContains: ['папа'], anyContains: ['50']),
  _Rule(priority: 80, itemKey: 'profile_mama_50', allContains: ['мама'], anyContains: ['50']),
  _Rule(priority: 80, itemKey: 'profile_papa_75', allContains: ['папа'], anyContains: ['75']),
  _Rule(priority: 80, itemKey: 'profile_mama_75', allContains: ['мама'], anyContains: ['75']),
  _Rule(priority: 80, itemKey: 'profile_papa_100', allContains: ['папа'], anyContains: ['100']),
  _Rule(priority: 80, itemKey: 'profile_mama_100', allContains: ['мама'], anyContains: ['100']),
];

String _normalize(String s) {
  return s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll('×', 'x')
      .replaceAll('х', 'x');
}

AliasHit? matchProductAlias(String rawName) {
  final text = _normalize(rawName);
  final sorted = [..._rules]..sort((a, b) => b.priority.compareTo(a.priority));
  for (final r in sorted) {
    if (r.noneContains.any(text.contains)) continue;
    if (r.allContains.isNotEmpty && !r.allContains.every(text.contains)) continue;
    if (r.anyContains.isNotEmpty && !r.anyContains.any(text.contains)) continue;
    if (r.regex.isNotEmpty &&
        !r.regex.any((p) => RegExp(p, caseSensitive: false).hasMatch(text))) {
      continue;
    }
    final hasPositive =
        r.allContains.isNotEmpty || r.anyContains.isNotEmpty || r.regex.isNotEmpty;
    if (!hasPositive) continue;
    final entry = catalogByItemKey(r.itemKey);
    return AliasHit(
      itemKey: r.itemKey,
      receiptUnit: r.receiptUnit,
      unitsPerPack: r.unitsPerPack,
      productName: entry?.displayName,
    );
  }
  return null;
}
