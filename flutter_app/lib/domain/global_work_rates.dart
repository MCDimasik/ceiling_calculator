import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'documentation_model.dart';

const _prefKey = 'global_work_rates_v1';

/// App-wide default work rates (отделка / услуги), separate from supplier materials.
class GlobalWorkRates {
  GlobalWorkRates._();

  static List<ProjectPriceLine> defaults() => [
        ProjectPriceLine(
          matchKey: 'finish_floor',
          name: 'Отделка пола',
          unit: 'м²',
          unitPrice: 700,
        ),
        ProjectPriceLine(
          matchKey: 'finish_wall',
          name: 'Отделка стен',
          unit: 'м²',
          unitPrice: 700,
        ),
        ProjectPriceLine(
          matchKey: 'finish_ceiling',
          name: 'Отделка потолка',
          unit: 'м²',
          unitPrice: 700,
        ),
        ProjectPriceLine(
          matchKey: 'work_demolition',
          name: 'Демонтаж / подготовка',
          unit: 'м²',
          unitPrice: 0,
        ),
        ProjectPriceLine(
          matchKey: 'work_other',
          name: 'Прочие работы',
          unit: 'шт',
          unitPrice: 0,
        ),
      ];

  static Future<List<ProjectPriceLine>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.isEmpty) return defaults();
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final out = list
          .map((e) => ProjectPriceLine.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return out.isEmpty ? defaults() : out;
    } catch (_) {
      return defaults();
    }
  }

  static Future<void> save(List<ProjectPriceLine> lines) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey,
      jsonEncode(lines.map((e) => e.toJson()).toList()),
    );
  }
}
