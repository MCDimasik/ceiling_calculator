import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _prefOpeningTemplates = 'finish_opening_templates_v1';

/// Saved opening size/kind for reuse across rooms.
class OpeningTemplate {
  const OpeningTemplate({
    required this.id,
    required this.name,
    required this.kind,
    required this.widthCm,
    required this.heightCm,
    this.sillHeightCm = 0,
  });

  final String id;
  final String name;
  final String kind; // door | window
  final double widthCm;
  final double heightCm;
  final double sillHeightCm;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'widthCm': widthCm,
        'heightCm': heightCm,
        'sillHeightCm': sillHeightCm,
      };

  factory OpeningTemplate.fromJson(Map<String, dynamic> j) => OpeningTemplate(
        id: j['id'] as String? ?? '',
        name: (j['name'] as String?)?.trim() ?? '',
        kind: j['kind'] as String? ?? 'door',
        widthCm: (j['widthCm'] as num?)?.toDouble() ?? 90,
        heightCm: (j['heightCm'] as num?)?.toDouble() ?? 210,
        sillHeightCm: (j['sillHeightCm'] as num?)?.toDouble() ?? 0,
      );
}

Future<List<OpeningTemplate>> loadOpeningTemplates() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_prefOpeningTemplates);
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .whereType<Map>()
        .map((e) => OpeningTemplate.fromJson(Map<String, dynamic>.from(e)))
        .where((t) => t.name.isNotEmpty && t.id.isNotEmpty)
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveOpeningTemplates(List<OpeningTemplate> templates) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _prefOpeningTemplates,
    jsonEncode(templates.map((t) => t.toJson()).toList()),
  );
}

Future<List<OpeningTemplate>> upsertOpeningTemplate(OpeningTemplate t) async {
  final list = await loadOpeningTemplates();
  final i = list.indexWhere((e) => e.id == t.id || e.name == t.name);
  if (i >= 0) {
    list[i] = t;
  } else {
    list.add(t);
  }
  list.sort((a, b) => a.name.compareTo(b.name));
  await saveOpeningTemplates(list);
  return list;
}

String newOpeningTemplateId() =>
    'ot_${DateTime.now().millisecondsSinceEpoch}';
