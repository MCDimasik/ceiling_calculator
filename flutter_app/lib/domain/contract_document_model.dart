import 'cost_calculator.dart';
import 'finish_layer_pricing.dart';
import 'finish_material_links.dart';
import 'finish_model.dart';
import 'models.dart';
import 'materials_calculator.dart';
import 'project_floors.dart';
import 'project_price_resolver.dart';
import 'room_finish_areas.dart';
import 'special_space.dart';
import 'surface_prep_layers.dart';
import 'work_rates_catalog.dart';
import 'work_rates_lookup.dart';

/// Key for per-line price overrides: `roomId|floor` / `walls` / `ceiling`.
String contractLinePriceKey({required int? roomId, required String scope}) =>
    '${roomId ?? 0}|$scope';

/// Official form layout vs simplified table export.
enum ContractFormStyle {
  avangardKs,
  simpleTable,
}

extension ContractFormStyleX on ContractFormStyle {
  String get labelRu => switch (this) {
        ContractFormStyle.avangardKs => 'КС-2 / КС-3 · форма Авангард',
        ContractFormStyle.simpleTable => 'Упрощённая таблица',
      };

  static ContractFormStyle parse(String? raw) => switch (raw) {
        'simple' => ContractFormStyle.simpleTable,
        _ => ContractFormStyle.avangardKs,
      };

  String get storageKey => switch (this) {
        ContractFormStyle.avangardKs => 'avangard',
        ContractFormStyle.simpleTable => 'simple',
      };
}

enum ProposalLineMode {
  single,
  byRoom,
  custom,
}

/// Order of by-room preview / export lines.
enum ContractLineSort {
  byRoom,
  byFloor,
  byFinish,
}

extension ContractLineSortX on ContractLineSort {
  String get labelRu => switch (this) {
        ContractLineSort.byRoom => 'По помещениям',
        ContractLineSort.byFloor => 'По этажам',
        ContractLineSort.byFinish => 'По виду отделки',
      };

  static ContractLineSort parse(String? raw) => switch (raw) {
        'floor' => ContractLineSort.byFloor,
        'finish' => ContractLineSort.byFinish,
        _ => ContractLineSort.byRoom,
      };

  String get storageKey => switch (this) {
        ContractLineSort.byRoom => 'room',
        ContractLineSort.byFloor => 'floor',
        ContractLineSort.byFinish => 'finish',
      };
}

extension ProposalLineModeX on ProposalLineMode {
  String get labelRu => switch (this) {
        ProposalLineMode.single => 'Одной строкой',
        ProposalLineMode.byRoom => 'По помещениям',
        ProposalLineMode.custom => 'Свои строки',
      };

  static ProposalLineMode parse(String? raw) => switch (raw) {
        'by_room' => ProposalLineMode.byRoom,
        'custom' => ProposalLineMode.custom,
        _ => ProposalLineMode.single,
      };

  String get storageKey => switch (this) {
        ProposalLineMode.single => 'single',
        ProposalLineMode.byRoom => 'by_room',
        ProposalLineMode.custom => 'custom',
      };
}

/// What the unit price in КП/КС represents.
enum ContractPriceComposition {
  /// Prices from finish module / catalog as entered (usually work rates).
  workOnly,

  /// Finish work rate + material ₽/м² from primary supplier (one combined line).
  workPlusMaterial,
}

extension ContractPriceCompositionX on ContractPriceComposition {
  String get labelRu => switch (this) {
        ContractPriceComposition.workOnly => 'Только работа',
        ContractPriceComposition.workPlusMaterial => 'Работа + материал',
      };

  String get helperRu => switch (this) {
        ContractPriceComposition.workOnly =>
          'В строку идёт цена из расчёта отделки / каталога работ.',
        ContractPriceComposition.workPlusMaterial =>
          'К цене работ добавляются привязанные материалы слоёв '
              '(расход × цена из прайса) → одна ₽/м². '
              'Если привязок нет — берётся материал секции из прайса. '
              'В режиме «по помещениям» цену строки можно поправить вручную.',
      };

  static ContractPriceComposition parse(String? raw) => switch (raw) {
        'work_plus_material' => ContractPriceComposition.workPlusMaterial,
        _ => ContractPriceComposition.workOnly,
      };

  String get storageKey => switch (this) {
        ContractPriceComposition.workOnly => 'work_only',
        ContractPriceComposition.workPlusMaterial => 'work_plus_material',
      };
}

class ContractWorkLine {
  const ContractWorkLine({
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    this.estimatePos = '',
    this.lineKey = '',
    this.section = '',
  });

  final String name;
  final String unit;
  final double quantity;
  final double unitPrice;
  final String estimatePos;

  /// Stable key for price overrides (`12|floor`).
  final String lineKey;

  /// Domain hint for catalog: `floor` / `walls` / `ceiling`.
  final String section;

  double get lineSum => quantity * unitPrice;

  ContractWorkLine copyWith({
    String? name,
    String? unit,
    double? quantity,
    double? unitPrice,
    String? estimatePos,
    String? lineKey,
    String? section,
  }) =>
      ContractWorkLine(
        name: name ?? this.name,
        unit: unit ?? this.unit,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        estimatePos: estimatePos ?? this.estimatePos,
        lineKey: lineKey ?? this.lineKey,
        section: section ?? this.section,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'unit': unit,
        'quantity': quantity,
        'unit_price': unitPrice,
        if (estimatePos.isNotEmpty) 'estimate_pos': estimatePos,
        if (lineKey.isNotEmpty) 'line_key': lineKey,
        if (section.isNotEmpty) 'section': section,
      };

  static ContractWorkLine fromJson(Map<String, dynamic> json) => ContractWorkLine(
        name: json['name'] as String? ?? '',
        unit: json['unit'] as String? ?? 'м2',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
        estimatePos: json['estimate_pos'] as String? ?? '',
        lineKey: json['line_key'] as String? ?? '',
        section: json['section'] as String? ?? '',
      );
}

/// Per-project settings for КП / КС-2 / простой акт.
/// User-merged by-room lines (several atomic scopes → one KP/KS row).
class ContractMergedLine {
  ContractMergedLine({
    required this.id,
    required this.sourceKeys,
    required this.name,
    required this.unitPrice,
    this.unit = 'м2',
  });

  String id;
  List<String> sourceKeys;
  String name;
  double unitPrice;
  String unit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'source_keys': sourceKeys,
        'name': name,
        'unit_price': unitPrice,
        'unit': unit,
      };

  static ContractMergedLine fromJson(Map<String, dynamic> json) =>
      ContractMergedLine(
        id: json['id'] as String? ?? '',
        sourceKeys: [
          for (final e in (json['source_keys'] as List? ?? const []))
            '$e',
        ],
        name: json['name'] as String? ?? '',
        unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
        unit: json['unit'] as String? ?? 'м2',
      );
}

class ContractDocumentSettings {
  ContractDocumentSettings({
    this.formStyle = ContractFormStyle.avangardKs,
    this.lineMode = ProposalLineMode.single,
    this.priceComposition = ContractPriceComposition.workOnly,
    this.workTitle = 'Выполнение работ по отделке помещений',
    this.scopeNote = '',
    this.unifiedPricePerM2 = 700,
    this.customLines = const [],
    Map<String, double>? linePriceOverrides,
    Map<String, String>? lineNameOverrides,
    List<ContractMergedLine>? mergedLines,
    this.lineSort = ContractLineSort.byRoom,
  })  : linePriceOverrides = linePriceOverrides ?? {},
        lineNameOverrides = lineNameOverrides ?? {},
        mergedLines = mergedLines ?? [];

  ContractFormStyle formStyle;
  ProposalLineMode lineMode;
  ContractPriceComposition priceComposition;
  String workTitle;
  String scopeNote;
  double unifiedPricePerM2;
  List<ContractWorkLine> customLines;

  /// Manual full unit-price overrides for by-room lines (`roomId|scope` → ₽/м²).
  /// When set, replaces auto work (+ material) for that line until cleared.
  Map<String, double> linePriceOverrides;

  /// Manual name overrides for by-room lines.
  Map<String, String> lineNameOverrides;

  /// Merged groups for by-room mode.
  List<ContractMergedLine> mergedLines;

  ContractLineSort lineSort;

  Map<String, dynamic> toJson() => {
        'form_style': formStyle.storageKey,
        'line_mode': lineMode.storageKey,
        'price_composition': priceComposition.storageKey,
        'work_title': workTitle,
        if (scopeNote.isNotEmpty) 'scope_note': scopeNote,
        'unified_price_m2': unifiedPricePerM2,
        'line_sort': lineSort.storageKey,
        if (customLines.isNotEmpty)
          'custom_lines': customLines.map((l) => l.toJson()).toList(),
        if (linePriceOverrides.isNotEmpty)
          'line_price_overrides': linePriceOverrides,
        if (lineNameOverrides.isNotEmpty)
          'line_name_overrides': lineNameOverrides,
        if (mergedLines.isNotEmpty)
          'merged_lines': mergedLines.map((m) => m.toJson()).toList(),
      };

  static ContractDocumentSettings fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return ContractDocumentSettings();
    final linesRaw = json['custom_lines'] as List? ?? [];
    final rawTitle = json['work_title'] as String?;
    // Migrate old ceiling-only / short defaults to the KS template wording.
    final title = (rawTitle == null ||
            rawTitle.isEmpty ||
            rawTitle.contains('подвесного потолка') ||
            rawTitle == 'Отделочные работы')
        ? 'Выполнение работ по отделке помещений'
        : rawTitle;
    final overridesRaw = json['line_price_overrides'];
    final overrides = <String, double>{};
    if (overridesRaw is Map) {
      for (final e in overridesRaw.entries) {
        final v = e.value;
        if (v is num) overrides['${e.key}'] = v.toDouble();
      }
    }
    final mergesRaw = json['merged_lines'] as List? ?? [];
    final nameOvRaw = json['line_name_overrides'];
    final nameOv = <String, String>{};
    if (nameOvRaw is Map) {
      for (final e in nameOvRaw.entries) {
        nameOv['${e.key}'] = '${e.value}';
      }
    }
    return ContractDocumentSettings(
      formStyle: ContractFormStyleX.parse(json['form_style'] as String?),
      lineMode: ProposalLineModeX.parse(json['line_mode'] as String?),
      priceComposition: ContractPriceCompositionX.parse(
        json['price_composition'] as String?,
      ),
      workTitle: title,
      scopeNote: json['scope_note'] as String? ?? '',
      unifiedPricePerM2: (json['unified_price_m2'] as num?)?.toDouble() ?? 700,
      customLines: linesRaw
          .whereType<Map>()
          .map((e) => ContractWorkLine.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      linePriceOverrides: overrides,
      lineNameOverrides: nameOv,
      mergedLines: mergesRaw
          .whereType<Map>()
          .map((e) => ContractMergedLine.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      lineSort: ContractLineSortX.parse(json['line_sort'] as String?),
    );
  }

  String workNameWithScope() {
    final note = scopeNote.trim();
    if (note.isEmpty) return workTitle;
    return '$workTitle. $note';
  }

  ContractDocumentSettings copyWith({
    ContractFormStyle? formStyle,
    ProposalLineMode? lineMode,
    ContractPriceComposition? priceComposition,
    String? workTitle,
    String? scopeNote,
    double? unifiedPricePerM2,
    List<ContractWorkLine>? customLines,
    Map<String, double>? linePriceOverrides,
    Map<String, String>? lineNameOverrides,
    List<ContractMergedLine>? mergedLines,
    ContractLineSort? lineSort,
  }) =>
      ContractDocumentSettings(
        formStyle: formStyle ?? this.formStyle,
        lineMode: lineMode ?? this.lineMode,
        priceComposition: priceComposition ?? this.priceComposition,
        workTitle: workTitle ?? this.workTitle,
        scopeNote: scopeNote ?? this.scopeNote,
        unifiedPricePerM2: unifiedPricePerM2 ?? this.unifiedPricePerM2,
        customLines: customLines ?? this.customLines,
        linePriceOverrides: linePriceOverrides ?? this.linePriceOverrides,
        lineNameOverrides: lineNameOverrides ?? this.lineNameOverrides,
        mergedLines: mergedLines ?? this.mergedLines,
        lineSort: lineSort ?? this.lineSort,
      );
}

/// «Кабинет · 1 этаж · Отделка пола» (+ опциональное уточнение scopeNote).
String formatContractScopeLineName({
  required String finishTitle,
  required String roomName,
  String? floorLabel,
  String scopeNote = '',
  String? override,
}) {
  if (override != null && override.trim().isNotEmpty) return override.trim();
  final parts = <String>[
    if (roomName.trim().isNotEmpty) roomName.trim(),
    if (floorLabel != null && floorLabel.trim().isNotEmpty) floorLabel.trim(),
    finishTitle,
  ];
  var name = parts.join(' · ');
  final note = scopeNote.trim();
  if (note.isNotEmpty) name = '$name. $note';
  return name;
}

List<ContractWorkLine> sortContractWorkLines(
  List<ContractWorkLine> lines,
  ContractLineSort sort,
) {
  int finishRank(String section) => switch (section) {
        'floor' => 0,
        'walls' => 1,
        'ceiling' => 2,
        _ => 9,
      };

  String floorKey(ContractWorkLine l) {
    // «Room · Floor · Finish» → middle part when present.
    final parts = l.name.split(' · ');
    if (parts.length >= 3) return parts[1];
    if (parts.length == 2 && !parts[1].startsWith('Отделка')) return parts[1];
    return '';
  }

  String roomKey(ContractWorkLine l) {
    final parts = l.name.split(' · ');
    return parts.isNotEmpty ? parts.first : l.name;
  }

  final out = List<ContractWorkLine>.from(lines);
  switch (sort) {
    case ContractLineSort.byRoom:
      out.sort((a, b) {
        final r = roomKey(a).compareTo(roomKey(b));
        if (r != 0) return r;
        return finishRank(a.section).compareTo(finishRank(b.section));
      });
    case ContractLineSort.byFloor:
      out.sort((a, b) {
        final f = floorKey(a).compareTo(floorKey(b));
        if (f != 0) return f;
        final r = roomKey(a).compareTo(roomKey(b));
        if (r != 0) return r;
        return finishRank(a.section).compareTo(finishRank(b.section));
      });
    case ContractLineSort.byFinish:
      out.sort((a, b) {
        final f = finishRank(a.section).compareTo(finishRank(b.section));
        if (f != 0) return f;
        return roomKey(a).compareTo(roomKey(b));
      });
  }
  return out;
}

/// Apply [mergedLines] onto atomic by-room lines.
List<ContractWorkLine> applyContractLineMerges(
  List<ContractWorkLine> lines,
  List<ContractMergedLine> merges,
) {
  if (merges.isEmpty) return lines;
  final consumed = <String>{};
  final out = <ContractWorkLine>[];
  final byKey = <String, ContractWorkLine>{
    for (final l in lines)
      if (l.lineKey.isNotEmpty) l.lineKey: l,
  };

  for (final merge in merges) {
    final parts = <ContractWorkLine>[
      for (final k in merge.sourceKeys)
        if (byKey.containsKey(k)) byKey[k]!,
    ];
    if (parts.length < 2) continue;
    for (final p in parts) {
      consumed.add(p.lineKey);
    }
    final qty = parts.fold<double>(0, (s, l) => s + l.quantity);
    out.add(
      ContractWorkLine(
        name: merge.name,
        unit: merge.unit,
        quantity: qty,
        unitPrice: merge.unitPrice,
        estimatePos: parts.first.estimatePos,
        lineKey: 'merge:${merge.id}',
        section: parts.first.section,
      ),
    );
  }

  for (final l in lines) {
    if (l.lineKey.isNotEmpty && consumed.contains(l.lineKey)) continue;
    out.add(l);
  }
  // Keep a stable-ish order: merges first in declaration order already appended
  // with remaining atomics in original order.
  return out;
}

double totalAreaM2(Iterable<Room> rooms) {
  var area = 0.0;
  for (final room in rooms) {
    if (!roomHasFinishGeometry(room)) continue;
    final a = resolveRoomFinishAreas(room);
    // Prefer floor; fall back to walls for stairwells without floor volume.
    final contrib = a.floorM2 > 0 ? a.floorM2 : a.wallsM2;
    area += contrib;
  }
  return area;
}

({double floor, double walls, double ceiling}) _scopeAreasM2(Iterable<Room> rooms) {
  var floor = 0.0;
  var walls = 0.0;
  var ceiling = 0.0;
  for (final room in rooms) {
    if (!roomHasFinishGeometry(room)) continue;
    final areas = resolveRoomFinishAreas(room);
    if (room.finishIncludeFloor) floor += areas.floorM2;
    if (room.finishIncludeWalls) walls += areas.wallsM2;
    if (room.finishIncludeCeiling) ceiling += areas.ceilingM2;
  }
  return (floor: floor, walls: walls, ceiling: ceiling);
}

/// Legacy fallback: one material ₽/м² from supplier section key.
double _sectionMaterialPerM2({
  required String scope,
  Map<String, SupplierPrice>? supplierPrices,
}) {
  if (supplierPrices == null || supplierPrices.isEmpty) return 0;
  final sectionKey = switch (scope) {
    'floor' => 'finish_floor',
    'walls' => 'finish_wall',
    'ceiling' => 'finish_ceiling',
    _ => '',
  };
  if (sectionKey.isEmpty) return 0;
  final hit = resolveFinishSupplierPrice(
    sectionKey: sectionKey,
    prices: supplierPrices,
  );
  final p = hit?.unitPriceClient ?? 0;
  return p > 0 ? p : 0;
}

List<FinishMaterialLink> _scopeMaterialLinks(Room room, String scope) {
  final out = <FinishMaterialLink>[];
  switch (scope) {
    case 'walls':
      for (final raw in room.wallFinishLayers) {
        final layer = FinishLayer.fromJson(Map<String, dynamic>.from(raw));
        if (!layer.enabled) continue;
        out.addAll(layer.materialLinks);
      }
    case 'floor':
      for (final raw in room.floorPrepLayers) {
        final layer =
            SurfacePrepLayer.fromJson(Map<String, dynamic>.from(raw));
        if (!layer.enabled) continue;
        out.addAll(layer.materialLinks);
      }
      out.addAll(decodeMaterialLinks(room.floorCoveringMaterials));
    case 'ceiling':
      for (final raw in room.ceilingPrepLayers) {
        final layer =
            SurfacePrepLayer.fromJson(Map<String, dynamic>.from(raw));
        if (!layer.enabled) continue;
        out.addAll(layer.materialLinks);
      }
      out.addAll(decodeMaterialLinks(room.ceilingSystemMaterials));
  }
  return out;
}

/// Material ₽/м² for a scope: Σ (qtyPerUnit × client price) of linked items.
/// If the scope has no links → section supplier price (`finish_*`).
double _materialPerM2({
  required Room room,
  required String scope,
  Map<String, SupplierPrice>? supplierPrices,
}) {
  if (supplierPrices == null || supplierPrices.isEmpty) return 0;
  final links = _scopeMaterialLinks(room, scope);
  if (links.isEmpty) {
    return _sectionMaterialPerM2(scope: scope, supplierPrices: supplierPrices);
  }
  var sum = 0.0;
  for (final m in links) {
    if (m.itemKey.isEmpty) continue;
    final p = supplierPrices[m.itemKey];
    final client = p?.unitPriceClient ?? 0;
    if (client <= 0) continue;
    final q = m.qtyPerUnit <= 0 ? 1.0 : m.qtyPerUnit;
    sum += q * client;
  }
  return sum;
}

double _roomScopeUnitPrice({
  required ContractDocumentSettings settings,
  required Room room,
  required String scope,
  List<WorkRateCategory>? catalog,
  Map<String, SupplierPrice>? supplierPrices,
}) {
  // Explicit manual override wins (full ₽/м² for the line, work+material).
  final key = contractLinePriceKey(roomId: room.id, scope: scope);
  final override = settings.linePriceOverrides[key];
  if (override != null && override > 0) {
    return override;
  }

  // Live finish module is the source of truth (layers + covering/system).
  double? fromFinish;
  if (scope == 'floor') {
    fromFinish = floorScopeUnitPrice(room);
  } else if (scope == 'walls') {
    fromFinish = sumLayerUnitPrices(
      room.wallFinishLayers.map(FinishLayer.fromJson),
    );
  } else if (scope == 'ceiling') {
    fromFinish = ceilingScopeUnitPrice(room);
    // Raw system price if area-based effective rate failed but price is set.
    fromFinish ??= ceilingSystemUnitPriceOf(room);
  }
  var work = fromFinish ?? 0;
  if (work <= 0 && catalog != null && catalog.isNotEmpty) {
    if (scope == 'floor') {
      final hit = matchFloorCoveringRate(room, catalog);
      if (hit != null && hit.unitPrice > 0) work = hit.unitPrice;
    } else if (scope == 'ceiling') {
      final hit = matchCeilingSystemRate(room, catalog);
      if (hit != null && hit.unitPrice > 0) work = hit.unitPrice;
    } else if (scope == 'walls') {
      final matched = catalogUnitPriceForLine(
        name: 'Отделка стен',
        section: scope,
        categories: catalog,
      );
      if (matched != null && matched > 0) work = matched;
    }
  }
  if (work <= 0) {
    // Special spaces without finish layers must not invent ₽ from unified rate.
    final specialBare = room.isSpecialSpace &&
        switch (scope) {
          'walls' => room.wallFinishLayers.isEmpty,
          'floor' =>
            room.floorPrepLayers.isEmpty &&
                (room.floorCoveringUnitPrice == null ||
                    room.floorCoveringUnitPrice! <= 0),
          'ceiling' =>
            room.ceilingPrepLayers.isEmpty &&
                (room.ceilingSystemUnitPrice == null ||
                    room.ceilingSystemUnitPrice! <= 0),
          _ => true,
        };
    if (!specialBare) work = settings.unifiedPricePerM2;
  }

  if (settings.priceComposition == ContractPriceComposition.workPlusMaterial) {
    work += _materialPerM2(
      room: room,
      scope: scope,
      supplierPrices: supplierPrices,
    );
  }
  return work;
}

List<ContractWorkLine> _linesFromScopeAreas({
  required ContractDocumentSettings settings,
  required double floor,
  required double walls,
  required double ceiling,
  String roomName = '',
  String? floorLabel,
  int startPos = 1,
  Room? room,
  List<WorkRateCategory>? catalog,
  Map<String, SupplierPrice>? supplierPrices,
}) {
  final out = <ContractWorkLine>[];
  var pos = startPos;
  void add(String title, String scope, double qty) {
    if (qty <= 0) return;
    final key = contractLinePriceKey(roomId: room?.id, scope: scope);
    final price = room != null
        ? _roomScopeUnitPrice(
            settings: settings,
            room: room,
            scope: scope,
            catalog: catalog,
            supplierPrices: supplierPrices,
          )
        : settings.unifiedPricePerM2;
    out.add(ContractWorkLine(
      name: formatContractScopeLineName(
        finishTitle: title,
        roomName: roomName,
        floorLabel: floorLabel,
        scopeNote: settings.scopeNote,
        override: settings.lineNameOverrides[key],
      ),
      unit: 'м2',
      quantity: qty,
      unitPrice: price,
      estimatePos: '$pos',
      lineKey: key,
      section: scope,
    ));
    pos++;
  }

  add('Отделка пола', 'floor', floor);
  add('Отделка стен', 'walls', walls);
  add('Отделка потолка', 'ceiling', ceiling);
  return out;
}

String roomLabelForDocs(Room room, List<ProjectFloor> floors) =>
    roomNameWithFloor(room: room, floors: floors);

/// Work lines for КП / КС from finish include flags (пол / стены / потолок).
///
/// [catalog] — optional work-rates catalog for by-room price suggestions.
/// [supplierPrices] — used when [ContractPriceComposition.workPlusMaterial].
List<ContractWorkLine> buildWorkLines({
  required ContractDocumentSettings settings,
  required Iterable<Room> rooms,
  List<ProjectFloor> floors = const [],
  List<WorkRateCategory>? catalog,
  Map<String, SupplierPrice>? supplierPrices,
}) {
  switch (settings.lineMode) {
    case ProposalLineMode.custom:
      // Only explicit custom lines — never invent a «одной строкой» ghost row.
      return List<ContractWorkLine>.from(settings.customLines);
    case ProposalLineMode.byRoom:
      final out = _buildByRoomAtomicLines(
        settings: settings,
        rooms: rooms,
        floors: floors,
        catalog: catalog,
        supplierPrices: supplierPrices,
      );
      if (out.isEmpty) return _fallbackSingle(settings, rooms);
      final merged = applyContractLineMerges(out, settings.mergedLines);
      return sortContractWorkLines(merged, settings.lineSort);
    case ProposalLineMode.single:
      // One line: quantity from rooms; unit price from the primary field
      // [unifiedPricePerM2]. UI seeds that field with the weighted average.
      final detail = _buildByRoomAtomicLines(
        settings: settings,
        rooms: rooms,
        floors: floors,
        catalog: catalog,
        supplierPrices: supplierPrices,
      );
      if (detail.isEmpty) return _fallbackSingle(settings, rooms);
      final qty = detail.fold<double>(0, (s, l) => s + l.quantity);
      final sum = detail.fold<double>(0, (s, l) => s + l.lineSum);
      if (qty <= 0) return _fallbackSingle(settings, rooms);
      final avg = sum / qty;
      final price = settings.unifiedPricePerM2 > 0
          ? settings.unifiedPricePerM2
          : avg;
      return [
        ContractWorkLine(
          name: settings.workNameWithScope(),
          unit: 'м2',
          quantity: qty,
          unitPrice: price,
          estimatePos: '1',
        ),
      ];
  }
}

/// Work lines for partial KS-2 closure: always room×scope atomics (as in smeta
/// «по помещениям»), filtered by [scopeIds] (`floor` / `walls` / `ceiling`).
/// Never includes vedomost material rows.
List<ContractWorkLine> buildScopedContractWorkLines({
  required ContractDocumentSettings settings,
  required Iterable<Room> rooms,
  required Set<String> scopeIds,
  List<ProjectFloor> floors = const [],
  List<WorkRateCategory>? catalog,
  Map<String, SupplierPrice>? supplierPrices,
}) {
  if (scopeIds.isEmpty) return const [];
  final atomics = _buildByRoomAtomicLines(
    settings: settings,
    rooms: rooms,
    floors: floors,
    catalog: catalog,
    supplierPrices: supplierPrices,
  );
  final filtered = [
    for (final l in atomics)
      if (scopeIds.contains(l.section)) l,
  ];
  if (filtered.isEmpty) return const [];
  final merges = settings.mergedLines
      .where((m) => m.sourceKeys.any((k) {
            final parts = k.split('|');
            return parts.length >= 2 && scopeIds.contains(parts.last);
          }))
      .toList();
  final merged = applyContractLineMerges(filtered, merges);
  return sortContractWorkLines(merged, settings.lineSort);
}

/// Weighted-average ₽/м² across by-room atomics (for seeding the single-line field).
double? weightedAverageUnitPrice({
  required ContractDocumentSettings settings,
  required Iterable<Room> rooms,
  List<ProjectFloor> floors = const [],
  List<WorkRateCategory>? catalog,
}) {
  final detail = _buildByRoomAtomicLines(
    settings: settings,
    rooms: rooms,
    floors: floors,
    catalog: catalog,
  );
  if (detail.isEmpty) return null;
  final qty = detail.fold<double>(0, (s, l) => s + l.quantity);
  final sum = detail.fold<double>(0, (s, l) => s + l.lineSum);
  if (qty <= 0) return null;
  return sum / qty;
}

/// Seed custom lines from current by-room atomics (names + qty + prices).
List<ContractWorkLine> seedCustomLinesFromRooms({
  required ContractDocumentSettings settings,
  required Iterable<Room> rooms,
  List<ProjectFloor> floors = const [],
  List<WorkRateCategory>? catalog,
}) {
  final atomics = _buildByRoomAtomicLines(
    settings: settings,
    rooms: rooms,
    floors: floors,
    catalog: catalog,
  );
  if (atomics.isEmpty) {
    return buildWorkLines(
      settings: settings.copyWith(lineMode: ProposalLineMode.single),
      rooms: rooms,
      floors: floors,
      catalog: catalog,
    );
  }
  return [
    for (var i = 0; i < atomics.length; i++)
      atomics[i].copyWith(estimatePos: '${i + 1}', lineKey: ''),
  ];
}

List<ContractWorkLine> _buildByRoomAtomicLines({
  required ContractDocumentSettings settings,
  required Iterable<Room> rooms,
  List<ProjectFloor> floors = const [],
  List<WorkRateCategory>? catalog,
  Map<String, SupplierPrice>? supplierPrices,
}) {
  final out = <ContractWorkLine>[];
  var pos = 1;
  for (final room in rooms) {
    if (!roomHasFinishGeometry(room)) continue;
    final floorLabel = roomFloorLabel(room: room, floors: floors);
    final areas = _scopeAreasM2([room]);
    final chunk = _linesFromScopeAreas(
      settings: settings,
      floor: areas.floor,
      walls: areas.walls,
      ceiling: areas.ceiling,
      roomName: room.name,
      floorLabel: floorLabel,
      startPos: pos,
      room: room,
      catalog: catalog,
      supplierPrices: supplierPrices,
    );
    if (chunk.isEmpty) {
      final area = MaterialsCalculator.roomAreaM2(room.walls);
      if (area > 0) {
        final key = contractLinePriceKey(roomId: room.id, scope: 'floor');
        out.add(ContractWorkLine(
          name: formatContractScopeLineName(
            finishTitle: settings.workTitle,
            roomName: room.name,
            floorLabel: floorLabel,
            scopeNote: settings.scopeNote,
            override: settings.lineNameOverrides[key],
          ),
          unit: 'м2',
          quantity: area,
          unitPrice: settings.unifiedPricePerM2,
          estimatePos: '$pos',
          lineKey: key,
          section: 'floor',
        ));
        pos++;
      }
    } else {
      out.addAll(chunk);
      pos += chunk.length;
    }
  }
  return out;
}

List<ContractWorkLine> _fallbackSingle(
  ContractDocumentSettings settings,
  Iterable<Room> rooms,
) {
  final area = totalAreaM2(rooms);
  return [
    ContractWorkLine(
      name: settings.workNameWithScope(),
      unit: 'м2',
      quantity: area,
      unitPrice: settings.unifiedPricePerM2,
      estimatePos: '1',
    ),
  ];
}

double linesTotal(Iterable<ContractWorkLine> lines) =>
    lines.fold<double>(0, (s, l) => s + l.lineSum);
