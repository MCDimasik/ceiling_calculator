import 'dart:convert';
import 'dart:math' as math;

/// Units for finish extra works / constructor lines.
enum FinishWorkUnit {
  m2('м²'),
  m('м'),
  pcs('шт'),
  set('компл'),
  kg('кг'),
  l('л');

  const FinishWorkUnit(this.labelRu);
  final String labelRu;

  static FinishWorkUnit parse(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    return switch (s) {
      'м²' || 'm2' || 'sqm' => FinishWorkUnit.m2,
      'м' || 'm' || 'lm' => FinishWorkUnit.m,
      'шт' || 'pcs' || 'pc' => FinishWorkUnit.pcs,
      'компл' || 'set' || 'комплект' => FinishWorkUnit.set,
      'кг' || 'kg' => FinishWorkUnit.kg,
      'л' || 'l' || 'litre' || 'liter' => FinishWorkUnit.l,
      _ => FinishWorkUnit.m2,
    };
  }
}

/// How quantity is obtained.
enum FinishWorkQtyMode {
  manual,
  measure;

  static FinishWorkQtyMode parse(String? raw) {
    return switch ((raw ?? '').trim()) {
      'measure' => FinishWorkQtyMode.measure,
      _ => FinishWorkQtyMode.manual,
    };
  }
}

/// Measure schema for constructor (dimensions in the work's natural unit).
enum FinishMeasureKind {
  /// length × width → area (м²)
  area,
  /// single length (м)
  length,
  /// length × height → area (м²) e.g. façade strip
  lengthHeight,
  /// count × norm per piece → result in [FinishWorkUnit]
  countNorm;

  static FinishMeasureKind parse(String? raw) {
    return switch ((raw ?? '').trim()) {
      'length' => FinishMeasureKind.length,
      // Legacy: L×H was a second area mode — treat as area (L×W fields).
      'lengthHeight' || 'length_height' => FinishMeasureKind.area,
      'countNorm' || 'count_norm' => FinishMeasureKind.countNorm,
      _ => FinishMeasureKind.area,
    };
  }
}

/// Optional measured inputs in **meters** (count/norm dimensionless).
class FinishWorkMeasure {
  const FinishWorkMeasure({
    this.kind = FinishMeasureKind.area,
    this.lengthM = 0,
    this.widthM = 0,
    this.heightM = 0,
    this.count = 0,
    this.normPerPiece = 1,
  });

  final FinishMeasureKind kind;
  final double lengthM;
  final double widthM;
  final double heightM;
  final double count;
  final double normPerPiece;

  /// Raw measured quantity in the unit implied by [kind] (before waste).
  double rawQuantity({required FinishWorkUnit unit}) {
    switch (kind) {
      case FinishMeasureKind.area:
        return lengthM * widthM;
      case FinishMeasureKind.length:
        return lengthM;
      case FinishMeasureKind.lengthHeight:
        return lengthM * heightM;
      case FinishMeasureKind.countNorm:
        return count * normPerPiece;
    }
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'lengthM': lengthM,
        'widthM': widthM,
        'heightM': heightM,
        'count': count,
        'normPerPiece': normPerPiece,
      };

  factory FinishWorkMeasure.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FinishWorkMeasure();
    // Prefer meters; migrate legacy centimetre fields if present.
    double dim(String mKey, String cmKey) {
      final m = (json[mKey] as num?)?.toDouble();
      if (m != null) return m;
      final cm = (json[cmKey] as num?)?.toDouble();
      if (cm != null) return cm / 100.0;
      return 0;
    }

    final rawKind = (json['kind'] as String?)?.trim() ?? '';
    final kind = FinishMeasureKind.parse(rawKind);
    var widthM = dim('widthM', 'widthCm');
    final heightM = dim('heightM', 'heightCm');
    // Migrated lengthHeight → area: second dimension lived in heightM.
    if ((rawKind == 'lengthHeight' || rawKind == 'length_height') &&
        widthM <= 0 &&
        heightM > 0) {
      widthM = heightM;
    }
    return FinishWorkMeasure(
      kind: kind,
      lengthM: dim('lengthM', 'lengthCm'),
      widthM: widthM,
      heightM: heightM,
      count: (json['count'] as num?)?.toDouble() ?? 0,
      normPerPiece: (json['normPerPiece'] as num?)?.toDouble() ?? 1,
    );
  }

  FinishWorkMeasure copyWith({
    FinishMeasureKind? kind,
    double? lengthM,
    double? widthM,
    double? heightM,
    double? count,
    double? normPerPiece,
  }) {
    return FinishWorkMeasure(
      kind: kind ?? this.kind,
      lengthM: lengthM ?? this.lengthM,
      widthM: widthM ?? this.widthM,
      heightM: heightM ?? this.heightM,
      count: count ?? this.count,
      normPerPiece: normPerPiece ?? this.normPerPiece,
    );
  }
}

/// One extra finish work line (project- or room-scoped).
class FinishExtraWork {
  FinishExtraWork({
    required this.id,
    required this.title,
    this.category = 'прочее',
    this.unit = FinishWorkUnit.m2,
    this.qtyMode = FinishWorkQtyMode.manual,
    this.manualQty = 0,
    this.wastePercent = 0,
    this.measure = const FinishWorkMeasure(),
    this.unitPrice,
    this.materialLabel,
    this.notes = '',
    this.roomId,
    this.templateId,
    this.sortIndex = 0,
  });

  final String id;
  String title;
  String category;
  FinishWorkUnit unit;
  FinishWorkQtyMode qtyMode;
  double manualQty;
  double wastePercent;
  FinishWorkMeasure measure;
  double? unitPrice;
  String? materialLabel;
  String notes;
  /// null → project scope (сводка объекта).
  int? roomId;
  String? templateId;
  int sortIndex;

  bool get isProjectScope => roomId == null;

  double get baseQuantity {
    if (qtyMode == FinishWorkQtyMode.manual) {
      return math.max(0, manualQty);
    }
    return math.max(0, measure.rawQuantity(unit: unit));
  }

  /// Quantity including waste (never less than base).
  double get quantityWithWaste {
    final w = wastePercent.clamp(0, 500);
    return baseQuantity * (1 + w / 100.0);
  }

  double? get lineTotal {
    final p = unitPrice;
    if (p == null) return null;
    return quantityWithWaste * p;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'unit': unit.name,
        'qtyMode': qtyMode.name,
        'manualQty': manualQty,
        'wastePercent': wastePercent,
        'measure': measure.toJson(),
        if (unitPrice != null) 'unitPrice': unitPrice,
        if (materialLabel != null) 'materialLabel': materialLabel,
        'notes': notes,
        if (roomId != null) 'roomId': roomId,
        if (templateId != null) 'templateId': templateId,
        'sortIndex': sortIndex,
      };

  factory FinishExtraWork.fromJson(Map<String, dynamic> json) {
    return FinishExtraWork(
      id: json['id'] as String? ?? _newId(),
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? 'прочее',
      unit: FinishWorkUnit.parse(json['unit'] as String?),
      qtyMode: FinishWorkQtyMode.parse(json['qtyMode'] as String?),
      manualQty: (json['manualQty'] as num?)?.toDouble() ?? 0,
      wastePercent: (json['wastePercent'] as num?)?.toDouble() ?? 0,
      measure: FinishWorkMeasure.fromJson(
        json['measure'] is Map
            ? Map<String, dynamic>.from(json['measure'] as Map)
            : null,
      ),
      unitPrice: (json['unitPrice'] as num?)?.toDouble(),
      materialLabel: json['materialLabel'] as String?,
      notes: json['notes'] as String? ?? '',
      roomId: json['roomId'] as int?,
      templateId: json['templateId'] as String?,
      sortIndex: json['sortIndex'] as int? ?? 0,
    );
  }

  FinishExtraWork copyWith({
    String? id,
    String? title,
    String? category,
    FinishWorkUnit? unit,
    FinishWorkQtyMode? qtyMode,
    double? manualQty,
    double? wastePercent,
    FinishWorkMeasure? measure,
    double? unitPrice,
    String? materialLabel,
    String? notes,
    int? roomId,
    bool clearRoomId = false,
    String? templateId,
    int? sortIndex,
  }) {
    return FinishExtraWork(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      qtyMode: qtyMode ?? this.qtyMode,
      manualQty: manualQty ?? this.manualQty,
      wastePercent: wastePercent ?? this.wastePercent,
      measure: measure ?? this.measure,
      unitPrice: unitPrice ?? this.unitPrice,
      materialLabel: materialLabel ?? this.materialLabel,
      notes: notes ?? this.notes,
      roomId: clearRoomId ? null : (roomId ?? this.roomId),
      templateId: templateId ?? this.templateId,
      sortIndex: sortIndex ?? this.sortIndex,
    );
  }
}

/// Reusable template for the work constructor.
class FinishWorkTemplate {
  FinishWorkTemplate({
    required this.id,
    required this.title,
    this.category = 'прочее',
    this.unit = FinishWorkUnit.m2,
    this.defaultWastePercent = 5,
    this.measureKind = FinishMeasureKind.area,
    this.notes = '',
  });

  final String id;
  String title;
  String category;
  FinishWorkUnit unit;
  double defaultWastePercent;
  FinishMeasureKind measureKind;
  String notes;

  FinishExtraWork toWork({int? roomId, int sortIndex = 0}) {
    return FinishExtraWork(
      id: _newId(),
      title: title,
      category: category,
      unit: unit,
      qtyMode: FinishWorkQtyMode.measure,
      wastePercent: defaultWastePercent,
      measure: FinishWorkMeasure(kind: measureKind),
      notes: notes,
      roomId: roomId,
      templateId: id,
      sortIndex: sortIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'unit': unit.name,
        'defaultWastePercent': defaultWastePercent,
        'measureKind': measureKind.name,
        'notes': notes,
      };

  factory FinishWorkTemplate.fromJson(Map<String, dynamic> json) {
    return FinishWorkTemplate(
      id: json['id'] as String? ?? _newId(),
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? 'прочее',
      unit: FinishWorkUnit.parse(json['unit'] as String?),
      defaultWastePercent:
          (json['defaultWastePercent'] as num?)?.toDouble() ?? 5,
      measureKind: FinishMeasureKind.parse(json['measureKind'] as String?),
      notes: json['notes'] as String? ?? '',
    );
  }
}

/// Project-level bag: works + user templates (seeded defaults always available).
class FinishExtraWorksState {
  FinishExtraWorksState({
    List<FinishExtraWork>? works,
    List<FinishWorkTemplate>? templates,
  })  : works = works ?? [],
        templates = templates ?? [];

  final List<FinishExtraWork> works;
  final List<FinishWorkTemplate> templates;

  /// Built-in seeds + user templates (user overrides same id).
  List<FinishWorkTemplate> get allTemplates {
    final byId = <String, FinishWorkTemplate>{
      for (final t in defaultFinishWorkTemplates) t.id: t,
      for (final t in templates) t.id: t,
    };
    return byId.values.toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  List<FinishExtraWork> projectWorks() {
    final list = works.where((w) => w.roomId == null).toList()
      ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    return list;
  }

  List<FinishExtraWork> roomWorks(int roomId) {
    final list = works.where((w) => w.roomId == roomId).toList()
      ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    return list;
  }

  Map<String, dynamic> toJson() => {
        'works': works.map((w) => w.toJson()).toList(),
        'templates': templates.map((t) => t.toJson()).toList(),
      };

  factory FinishExtraWorksState.fromJson(Map<String, dynamic>? json) {
    if (json == null) return FinishExtraWorksState();
    final worksRaw = json['works'];
    final templatesRaw = json['templates'];
    return FinishExtraWorksState(
      works: worksRaw is List
          ? worksRaw
              .whereType<Map>()
              .map((e) => FinishExtraWork.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : [],
      templates: templatesRaw is List
          ? templatesRaw
              .whereType<Map>()
              .map(
                (e) => FinishWorkTemplate.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
          : [],
    );
  }

  static FinishExtraWorksState decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return FinishExtraWorksState();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return FinishExtraWorksState.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {}
    return FinishExtraWorksState();
  }

  String encode() => jsonEncode(toJson());
}

/// Preset categories for the constructor UI.
const finishWorkCategoryPresets = <String>[
  'улица',
  'металлоконструкции',
  'фасад',
  'общестроительные',
  'прочее',
];

/// Seed templates (always listed; not stored unless customized).
final defaultFinishWorkTemplates = <FinishWorkTemplate>[
  FinishWorkTemplate(
    id: 'seed_outdoor_tile',
    title: 'Плитка наружная',
    category: 'улица',
    unit: FinishWorkUnit.m2,
    defaultWastePercent: 10,
    measureKind: FinishMeasureKind.area,
  ),
  FinishWorkTemplate(
    id: 'seed_rail_paint',
    title: 'Окраска перил',
    category: 'металлоконструкции',
    unit: FinishWorkUnit.m,
    defaultWastePercent: 5,
    measureKind: FinishMeasureKind.length,
  ),
  FinishWorkTemplate(
    id: 'seed_paint_m2',
    title: 'Покраска',
    category: 'прочее',
    unit: FinishWorkUnit.m2,
    defaultWastePercent: 5,
    measureKind: FinishMeasureKind.area,
  ),
  FinishWorkTemplate(
    id: 'seed_plaster_m2',
    title: 'Штукатурка',
    category: 'общестроительные',
    unit: FinishWorkUnit.m2,
    defaultWastePercent: 7,
    measureKind: FinishMeasureKind.area,
  ),
];

String _newId() =>
    'w_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(1 << 20)}';

String newFinishWorkId() => _newId();

String formatFinishWorkQty(double value, FinishWorkUnit unit) {
  if (unit == FinishWorkUnit.m2 || unit == FinishWorkUnit.m) {
    return value.toStringAsFixed(2);
  }
  if (value == value.roundToDouble()) return '${value.round()}';
  return value.toStringAsFixed(1);
}
