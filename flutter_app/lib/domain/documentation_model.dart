/// Closing / as-built documentation for **full finishing** (walls, floor, ceiling).
library;

import 'project_stage.dart';
import 'contract_document_model.dart';

/// Project-level stamp fields — common practice for Russian as-built drawings.
class DocumentationStamp {
  DocumentationStamp({
    this.objectName = '',
    this.customer = '',
    this.address = '',
    this.executor = '',
    this.designer = '',
    this.documentNumber = '',
    this.sheetTitle = 'Исполнительная документация по отделке',
    this.scaleNote = 'Без масштаба. Размеры по чертежу, мм.',
    DateTime? issueDate,
  }) : issueDate = issueDate ?? DateTime.now();

  String objectName;
  String customer;
  String address;
  String executor;
  String designer;
  String documentNumber;
  String sheetTitle;
  String scaleNote;
  DateTime issueDate;

  Map<String, dynamic> toJson() => {
        'object_name': objectName,
        'customer': customer,
        'address': address,
        'executor': executor,
        'designer': designer,
        'document_number': documentNumber,
        'sheet_title': sheetTitle,
        'scale_note': scaleNote,
        'issue_date': issueDate.toIso8601String(),
      };

  static DocumentationStamp fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return DocumentationStamp();
    return DocumentationStamp(
      objectName: json['object_name'] as String? ?? '',
      customer: json['customer'] as String? ?? '',
      address: json['address'] as String? ?? '',
      executor: json['executor'] as String? ?? '',
      designer: json['designer'] as String? ?? '',
      documentNumber: json['document_number'] as String? ?? '',
      sheetTitle: json['sheet_title'] as String? ??
          'Исполнительная документация по отделке',
      scaleNote: json['scale_note'] as String? ??
          'Без масштаба. Размеры по чертежу, мм.',
      issueDate: DateTime.tryParse(json['issue_date'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  DocumentationStamp copyWith({
    String? objectName,
    String? customer,
    String? address,
    String? executor,
    String? designer,
    String? documentNumber,
    String? sheetTitle,
    String? scaleNote,
    DateTime? issueDate,
  }) {
    return DocumentationStamp(
      objectName: objectName ?? this.objectName,
      customer: customer ?? this.customer,
      address: address ?? this.address,
      executor: executor ?? this.executor,
      designer: designer ?? this.designer,
      documentNumber: documentNumber ?? this.documentNumber,
      sheetTitle: sheetTitle ?? this.sheetTitle,
      scaleNote: scaleNote ?? this.scaleNote,
      issueDate: issueDate ?? this.issueDate,
    );
  }

  DocumentationStamp withDefaults({required String projectName, required String roomName}) {
    return copyWith(
      objectName: objectName.isEmpty ? projectName : objectName,
    );
  }

  List<(String, String)> stampLines({required String roomName}) => [
        ('Наименование документа', sheetTitle),
        ('Объект', objectName),
        ('Помещение', roomName),
        if (customer.isNotEmpty) ('Заказчик', customer),
        if (address.isNotEmpty) ('Адрес', address),
        if (executor.isNotEmpty) ('Исполнитель', executor),
        if (designer.isNotEmpty) ('Проектировщик', designer),
        if (documentNumber.isNotEmpty) ('№ документа', documentNumber),
        ('Дата', _formatDate(issueDate)),
        ('Масштаб', scaleNote),
      ];

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

/// Per-room checklist: design progress, hidden-works photos, acceptance.
enum RoomFieldPriority { normal, urgent, blocked }

extension RoomFieldPriorityX on RoomFieldPriority {
  String get labelRu => switch (this) {
        RoomFieldPriority.normal => 'Обычный',
        RoomFieldPriority.urgent => 'Срочно',
        RoomFieldPriority.blocked => 'Стоп',
      };

  static RoomFieldPriority parse(String? raw) => switch (raw) {
        'urgent' => RoomFieldPriority.urgent,
        'blocked' => RoomFieldPriority.blocked,
        _ => RoomFieldPriority.normal,
      };
}

class RoomDocumentationChecklist {
  RoomDocumentationChecklist({
    this.acceptedForHandover = false,
    this.notes = '',
    this.assignee = '',
    this.priority = RoomFieldPriority.normal,
    this.stepNotes = const {},
    this.stepPhotos = const {},
    this.hiddenWorksConfirmed = const {},
    this.manualTasks = const [],
    this.dueDate,
  });

  bool acceptedForHandover;
  String notes;

  /// Foreman assignment: brigade member or subcontractor name.
  String assignee;
  RoomFieldPriority priority;
  Map<String, String> stepNotes;

  /// Foreman-created tasks (offline, per room).
  List<ManualFieldTask> manualTasks;

  /// Optional deadline for hidden-works completion on this room.
  DateTime? dueDate;

  /// Local file paths keyed by [DocumentationStep.id].
  Map<String, List<String>> stepPhotos;

  /// Manual «выполнено» for hidden-works steps (when photo not required).
  Map<String, bool> hiddenWorksConfirmed;

  Map<String, dynamic> toJson() => {
        'accepted': acceptedForHandover,
        'notes': notes,
        'assignee': assignee,
        'priority': priority.name,
        'step_notes': stepNotes,
        'step_photos': stepPhotos.map((k, v) => MapEntry(k, v)),
        'hidden_works_confirmed': hiddenWorksConfirmed,
        'manual_tasks': manualTasks.map((t) => t.toJson()).toList(),
        if (dueDate != null) 'due_date': dueDate!.toIso8601String(),
      };

  static RoomDocumentationChecklist fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return RoomDocumentationChecklist();
    final rawNotes = json['step_notes'];
    final rawPhotos = json['step_photos'];
    final rawHw = json['hidden_works_confirmed'];
    return RoomDocumentationChecklist(
      acceptedForHandover: json['accepted'] as bool? ?? false,
      notes: json['notes'] as String? ?? '',
      assignee: json['assignee'] as String? ?? '',
      priority: RoomFieldPriorityX.parse(json['priority'] as String?),
      stepNotes: rawNotes is Map
          ? rawNotes.map((k, v) => MapEntry(k.toString(), v.toString()))
          : {},
      stepPhotos: _parsePhotos(rawPhotos),
      hiddenWorksConfirmed: rawHw is Map
          ? rawHw.map((k, v) => MapEntry(k.toString(), v == true))
          : {},
      manualTasks: _parseManualTasks(json['manual_tasks']),
      dueDate: DateTime.tryParse(json['due_date'] as String? ?? ''),
    );
  }

  static List<ManualFieldTask> _parseManualTasks(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => ManualFieldTask.fromJson(Map<String, dynamic>.from(e)))
        .where((t) => t.message.isNotEmpty)
        .toList();
  }

  static Map<String, List<String>> _parsePhotos(Object? raw) {
    if (raw is! Map) return {};
    final out = <String, List<String>>{};
    for (final e in raw.entries) {
      final list = e.value;
      if (list is List) {
        out[e.key.toString()] = list.map((x) => x.toString()).toList();
      }
    }
    return out;
  }

  List<String> photosFor(String stepId) => stepPhotos[stepId] ?? [];

  bool hiddenWorkDone(String stepId) =>
      (stepPhotos[stepId]?.isNotEmpty ?? false) ||
      (hiddenWorksConfirmed[stepId] ?? false);
}

/// Per-room export template paths (stored in [Room.documentationChecklistJson]).
class RoomExportTemplates {
  RoomExportTemplates({
    this.ks2TemplatePath,
    this.actHiddenTemplatePath,
    this.vedomostTemplatePath,
  });

  String? ks2TemplatePath;
  String? actHiddenTemplatePath;
  String? vedomostTemplatePath;

  bool get isEmpty =>
      (ks2TemplatePath == null || ks2TemplatePath!.isEmpty) &&
      (actHiddenTemplatePath == null || actHiddenTemplatePath!.isEmpty) &&
      (vedomostTemplatePath == null || vedomostTemplatePath!.isEmpty);

  bool get hasAnyOverride => !isEmpty;

  static RoomExportTemplates fromChecklistJson(Map<String, dynamic>? json) {
    final raw = json?['export_templates'];
    if (raw is! Map) return RoomExportTemplates();
    return RoomExportTemplates(
      ks2TemplatePath: raw['ks2'] as String?,
      actHiddenTemplatePath: raw['act_hidden'] as String?,
      vedomostTemplatePath: raw['vedomost'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (ks2TemplatePath != null && ks2TemplatePath!.isNotEmpty)
          'ks2': ks2TemplatePath,
        if (actHiddenTemplatePath != null && actHiddenTemplatePath!.isNotEmpty)
          'act_hidden': actHiddenTemplatePath,
        if (vedomostTemplatePath != null && vedomostTemplatePath!.isNotEmpty)
          'vedomost': vedomostTemplatePath,
      };

  static Map<String, dynamic> mergeIntoChecklist(
    Map<String, dynamic>? checklistJson,
    RoomExportTemplates templates,
  ) {
    final m = Map<String, dynamic>.from(checklistJson ?? {});
    if (templates.isEmpty) {
      m.remove('export_templates');
    } else {
      m['export_templates'] = templates.toJson();
    }
    return m;
  }
}

/// Persist checklist fields without dropping per-room [RoomExportTemplates].
Map<String, dynamic> roomChecklistJsonForSave(
  RoomDocumentationChecklist checklist,
  Map<String, dynamic>? existingJson,
) {
  final templates = RoomExportTemplates.fromChecklistJson(existingJson);
  return RoomExportTemplates.mergeIntoChecklist(checklist.toJson(), templates);
}

class ManualFieldTask {
  ManualFieldTask({
    required this.id,
    required this.message,
    this.done = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String message;
  bool done;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'message': message,
        'done': done,
        'created_at': createdAt.toIso8601String(),
      };

  static ManualFieldTask fromJson(Map<String, dynamic> json) => ManualFieldTask(
        id: json['id'] as String? ?? '',
        message: json['message'] as String? ?? '',
        done: json['done'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

enum DocumentationStepKind { auto, manual, hiddenWork }

enum DocumentationPhase { design, hiddenWorks, acceptance }

class DocumentationStep {
  const DocumentationStep({
    required this.id,
    required this.title,
    required this.kind,
    required this.phase,
    this.optional = false,
  });

  final String id;
  final String title;
  final DocumentationStepKind kind;
  final DocumentationPhase phase;
  final bool optional;

  // --- Проект / раскладка ---
  static const drawing = DocumentationStep(
    id: 'drawing',
    title: 'Чертёж помещения',
    kind: DocumentationStepKind.auto,
    phase: DocumentationPhase.design,
  );
  static const wallsPlan = DocumentationStep(
    id: 'walls_plan',
    title: 'Стены: слои отделки',
    kind: DocumentationStepKind.auto,
    phase: DocumentationPhase.design,
  );
  static const floorPlan = DocumentationStep(
    id: 'floor_plan',
    title: 'Пол: материал и раскладка',
    kind: DocumentationStepKind.auto,
    phase: DocumentationPhase.design,
  );
  static const ceilingFrame = DocumentationStep(
    id: 'ceiling_frame',
    title: 'Потолок: каркас / направляющие',
    kind: DocumentationStepKind.auto,
    phase: DocumentationPhase.design,
    optional: true,
  );
  static const ceilingLayout = DocumentationStep(
    id: 'ceiling_layout',
    title: 'Потолок: раскладка плит',
    kind: DocumentationStepKind.auto,
    phase: DocumentationPhase.design,
  );
  static const ceilingLights = DocumentationStep(
    id: 'ceiling_lights',
    title: 'Потолок: светильники',
    kind: DocumentationStepKind.auto,
    phase: DocumentationPhase.design,
    optional: true,
  );
  static const materials = DocumentationStep(
    id: 'materials',
    title: 'Ведомость материалов (комплекс)',
    kind: DocumentationStepKind.auto,
    phase: DocumentationPhase.design,
  );

  // --- Скрытые работы (фото) ---
  static const hwWalls = DocumentationStep(
    id: 'hw_walls',
    title: 'Скрытые: подготовка / отделка стен',
    kind: DocumentationStepKind.hiddenWork,
    phase: DocumentationPhase.hiddenWorks,
  );
  static const hwFloor = DocumentationStep(
    id: 'hw_floor',
    title: 'Скрытые: стяжка / выравнивание / пол',
    kind: DocumentationStepKind.hiddenWork,
    phase: DocumentationPhase.hiddenWorks,
  );
  static const hwCeilingFrame = DocumentationStep(
    id: 'hw_ceiling_frame',
    title: 'Скрытые: каркас потолка',
    kind: DocumentationStepKind.hiddenWork,
    phase: DocumentationPhase.hiddenWorks,
    optional: true,
  );
  static const hwCeilingGuides = DocumentationStep(
    id: 'hw_ceiling_guides',
    title: 'Скрытые: направляющие',
    kind: DocumentationStepKind.hiddenWork,
    phase: DocumentationPhase.hiddenWorks,
    optional: true,
  );
  static const hwCeilingLights = DocumentationStep(
    id: 'hw_ceiling_lights',
    title: 'Скрытые: закладные / свет',
    kind: DocumentationStepKind.hiddenWork,
    phase: DocumentationPhase.hiddenWorks,
    optional: true,
  );
  static const hwCeilingTiles = DocumentationStep(
    id: 'hw_ceiling_tiles',
    title: 'Скрытые: плиты / кассеты',
    kind: DocumentationStepKind.hiddenWork,
    phase: DocumentationPhase.hiddenWorks,
    optional: true,
  );

  static const accepted = DocumentationStep(
    id: 'accepted',
    title: 'Комплекс сдан / готово к акту',
    kind: DocumentationStepKind.manual,
    phase: DocumentationPhase.acceptance,
  );

  static const all = [
    drawing,
    wallsPlan,
    floorPlan,
    ceilingFrame,
    ceilingLayout,
    ceilingLights,
    materials,
    hwWalls,
    hwFloor,
    hwCeilingFrame,
    hwCeilingGuides,
    hwCeilingLights,
    hwCeilingTiles,
    accepted,
  ];

  static const hiddenWorks = [
    hwWalls,
    hwFloor,
    hwCeilingFrame,
    hwCeilingGuides,
    hwCeilingLights,
    hwCeilingTiles,
  ];
}

enum AsBuiltSchemeKind { ceiling, floor, walls, combined }

extension AsBuiltSchemeKindX on AsBuiltSchemeKind {
  String get labelRu => switch (this) {
        AsBuiltSchemeKind.ceiling => 'Потолок',
        AsBuiltSchemeKind.floor => 'Пол',
        AsBuiltSchemeKind.walls => 'Стены',
        AsBuiltSchemeKind.combined => 'Отделка',
      };
}

/// Document categories in the per-project vault feed.
enum DocumentVaultCategory {
  kp,
  smeta,
  ks2,
  ks3,
  act,
  scheme,
  certificate,
  other;

  String get labelRu => switch (this) {
        DocumentVaultCategory.kp => 'КП',
        DocumentVaultCategory.smeta => 'Сметы / ведомости',
        DocumentVaultCategory.ks2 => 'КС-2',
        DocumentVaultCategory.ks3 => 'КС-3',
        DocumentVaultCategory.act => 'Акты',
        DocumentVaultCategory.scheme => 'Схемы',
        DocumentVaultCategory.certificate => 'Сертификаты',
        DocumentVaultCategory.other => 'Прочее',
      };

  static DocumentVaultCategory parse(String? raw) {
    for (final v in DocumentVaultCategory.values) {
      if (v.name == raw) return v;
    }
    return DocumentVaultCategory.other;
  }
}

enum DocumentVaultSource {
  export,
  import,
  attachment,
  certificate;

  String get labelRu => switch (this) {
        DocumentVaultSource.export => 'Экспорт',
        DocumentVaultSource.import => 'Импорт',
        DocumentVaultSource.attachment => 'Вложение',
        DocumentVaultSource.certificate => 'Сертификат',
      };

  static DocumentVaultSource parse(String? raw) {
    for (final v in DocumentVaultSource.values) {
      if (v.name == raw) return v;
    }
    return DocumentVaultSource.attachment;
  }
}

/// File registered in the project's documents vault.
class ProjectVaultEntry {
  ProjectVaultEntry({
    required this.id,
    required this.category,
    required this.name,
    required this.relativePath,
    required this.createdAt,
    required this.source,
    this.roomId,
    this.absolutePathHint,
  });

  final String id;
  final DocumentVaultCategory category;
  final String name;
  final String relativePath;
  final DateTime createdAt;
  final DocumentVaultSource source;
  final int? roomId;
  final String? absolutePathHint;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.name,
        'name': name,
        'relative_path': relativePath,
        'created_at': createdAt.toIso8601String(),
        'source': source.name,
        if (roomId != null) 'room_id': roomId,
        if (absolutePathHint != null) 'absolute_path': absolutePathHint,
      };

  static ProjectVaultEntry fromJson(Map<String, dynamic> json) =>
      ProjectVaultEntry(
        id: json['id'] as String? ?? '',
        category: DocumentVaultCategory.parse(json['category'] as String?),
        name: json['name'] as String? ?? '',
        relativePath: json['relative_path'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        source: DocumentVaultSource.parse(json['source'] as String?),
        roomId: (json['room_id'] as num?)?.toInt(),
        absolutePathHint: json['absolute_path'] as String?,
      );
}

/// Certificate file attached to a material type at project level.
class MaterialCertificate {
  MaterialCertificate({
    required this.materialKey,
    required this.label,
    required this.localPath,
    this.uploadedAt,
  });

  final String materialKey;
  final String label;
  final String localPath;
  final DateTime? uploadedAt;

  Map<String, dynamic> toJson() => {
        'material_key': materialKey,
        'label': label,
        'local_path': localPath,
        'uploaded_at': uploadedAt?.toIso8601String(),
      };

  static MaterialCertificate fromJson(Map<String, dynamic> json) {
    return MaterialCertificate(
      materialKey: json['material_key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      localPath: json['local_path'] as String? ?? '',
      uploadedAt: DateTime.tryParse(json['uploaded_at'] as String? ?? ''),
    );
  }
}

/// Contract / estimate metadata for KS-2 and KS-3 (per project).
class ProjectContractInfo {
  ProjectContractInfo({
    this.contractNumber = '',
    this.estimateNumber = '',
    this.customerInn = '',
    this.customerOkpo = '',
    this.customerName = '',
    this.buildSite = '',
    this.contractDate,
    this.investorOkpo = '22622328',
    this.vatRatePercent = 20,
    this.vatExempt = true,
  });

  String contractNumber;
  String estimateNumber;
  String customerInn;
  String customerOkpo;
  String customerName;
  String buildSite;
  DateTime? contractDate;
  String investorOkpo;
  double vatRatePercent;

  /// When true, documents show «Без НДС» (typical for ИП on УСН).
  bool vatExempt;

  Map<String, dynamic> toJson() => {
        'contract_number': contractNumber,
        'estimate_number': estimateNumber,
        'customer_inn': customerInn,
        if (customerOkpo.isNotEmpty) 'customer_okpo': customerOkpo,
        if (customerName.isNotEmpty) 'customer_name': customerName,
        if (buildSite.isNotEmpty) 'build_site': buildSite,
        if (contractDate != null) 'contract_date': contractDate!.toIso8601String(),
        if (investorOkpo.isNotEmpty) 'investor_okpo': investorOkpo,
        'vat_rate_percent': vatRatePercent,
        if (vatExempt) 'vat_exempt': true,
      };

  static ProjectContractInfo fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return ProjectContractInfo();
    return ProjectContractInfo(
      contractNumber: json['contract_number'] as String? ?? '',
      estimateNumber: json['estimate_number'] as String? ?? '',
      customerInn: json['customer_inn'] as String? ?? '',
      customerOkpo: json['customer_okpo'] as String? ?? '',
      customerName: json['customer_name'] as String? ?? '',
      buildSite: json['build_site'] as String? ?? '',
      contractDate: DateTime.tryParse(json['contract_date'] as String? ?? ''),
      investorOkpo: json['investor_okpo'] as String? ?? '22622328',
      vatRatePercent: (json['vat_rate_percent'] as num?)?.toDouble() ?? 20,
      vatExempt: json['vat_exempt'] as bool? ?? true,
    );
  }
}

/// Per-project unit rate for KS-2 / KS-3 (overrides global supplier prices).
class ProjectPriceLine {
  ProjectPriceLine({
    required this.matchKey,
    required this.name,
    this.unit = 'шт',
    this.unitPrice = 0,
  });

  /// Catalog calc key, finish_floor / finish_wall / finish_ceiling / purchase, or custom.
  String matchKey;
  String name;
  String unit;
  double unitPrice;

  Map<String, dynamic> toJson() => {
        'match_key': matchKey,
        'name': name,
        'unit': unit,
        'unit_price': unitPrice,
      };

  static ProjectPriceLine fromJson(Map<String, dynamic> json) {
    return ProjectPriceLine(
      matchKey: json['match_key'] as String? ?? '',
      name: json['name'] as String? ?? '',
      unit: json['unit'] as String? ?? 'шт',
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Status of a registered KS-2 act on the project ledger.
enum Ks2ActStatus {
  issued,
  paid,
  cancelled;

  String get labelRu => switch (this) {
        Ks2ActStatus.issued => 'Выставлен',
        Ks2ActStatus.paid => 'Оплачен',
        Ks2ActStatus.cancelled => 'Отменён',
      };

  static Ks2ActStatus parse(String? raw) => switch (raw) {
        'paid' => Ks2ActStatus.paid,
        'cancelled' => Ks2ActStatus.cancelled,
        _ => Ks2ActStatus.issued,
      };
}

/// One intermediate KS-2 closure at project level (aggregates rooms × scope).
class Ks2ActRecord {
  Ks2ActRecord({
    required this.id,
    required this.actNumber,
    required this.scope,
    required this.roomIds,
    required this.roomNames,
    required this.totalAmount,
    required this.createdAt,
    this.status = Ks2ActStatus.issued,
    this.exportPath,
    this.notes = '',
    this.amendedFromId,
    this.scopeBreakdown = const {},
  });

  final String id;
  final int actNumber;
  final String scope;
  final List<int> roomIds;
  final List<String> roomNames;
  final double totalAmount;
  final DateTime createdAt;
  final Ks2ActStatus status;
  final String? exportPath;
  final String notes;
  final String? amendedFromId;
  final Map<String, double> scopeBreakdown;

  Map<String, dynamic> toJson() => {
        'id': id,
        'act_number': actNumber,
        'scope': scope,
        'room_ids': roomIds,
        'room_names': roomNames,
        'total_amount': totalAmount,
        'created_at': createdAt.toIso8601String(),
        'status': status.name,
        if (exportPath != null && exportPath!.isNotEmpty) 'export_path': exportPath,
        if (notes.isNotEmpty) 'notes': notes,
        if (amendedFromId != null && amendedFromId!.isNotEmpty) 'amended_from_id': amendedFromId,
        if (scopeBreakdown.isNotEmpty)
          'scope_breakdown': scopeBreakdown.map((k, v) => MapEntry(k, v)),
      };

  static Ks2ActRecord fromJson(Map<String, dynamic> json) {
    final breakdownRaw = json['scope_breakdown'];
    final breakdown = <String, double>{};
    if (breakdownRaw is Map) {
      for (final e in breakdownRaw.entries) {
        final v = (e.value as num?)?.toDouble();
        if (v != null) breakdown[e.key.toString()] = v;
      }
    }
    return Ks2ActRecord(
        id: json['id'] as String? ?? '',
        actNumber: (json['act_number'] as num?)?.toInt() ?? 0,
        scope: json['scope'] as String? ?? '',
        roomIds: (json['room_ids'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [],
        roomNames: (json['room_names'] as List?)?.map((e) => e.toString()).toList() ?? [],
        totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
        status: Ks2ActStatus.parse(json['status'] as String?),
        exportPath: json['export_path'] as String?,
        notes: json['notes'] as String? ?? '',
        amendedFromId: json['amended_from_id'] as String?,
        scopeBreakdown: breakdown,
      );
  }
}

class ProjectDocumentation {
  ProjectDocumentation({
    DocumentationStamp? stamp,
    ProjectContractInfo? contract,
    this.vedomostTemplatePath,
    this.ks2TemplatePath,
    this.ks3TemplatePath,
    this.actHiddenTemplatePath,
    List<MaterialCertificate>? certificates,
    List<ProjectPriceLine>? ks2Prices,
    List<Ks2ActRecord>? ks2Acts,
    List<String>? enabledWorkScopes,
    this.useProjectPricesOnly = false,
    this.requireFullKs2Pricing = false,
    this.stage = ProjectStage.design,
    this.nextActNumber = 1,
    this.primarySupplierId,
    ContractDocumentSettings? contractDocs,
    List<ProjectVaultEntry>? vault,
  })  : stamp = stamp ?? DocumentationStamp(),
        contract = contract ?? ProjectContractInfo(),
        certificates = certificates ?? [],
        ks2Prices = ks2Prices ?? [],
        ks2Acts = ks2Acts ?? [],
        enabledWorkScopes = enabledWorkScopes ?? const ['floor', 'walls', 'ceiling'],
        contractDocs = contractDocs ?? ContractDocumentSettings(),
        vault = vault ?? [];

  DocumentationStamp stamp;
  ProjectContractInfo contract;
  String? vedomostTemplatePath;
  String? ks2TemplatePath;
  String? ks3TemplatePath;
  String? actHiddenTemplatePath;
  List<MaterialCertificate> certificates;
  List<ProjectPriceLine> ks2Prices;

  /// Per-project documents vault (exports, attachments).
  List<ProjectVaultEntry> vault;

  /// When true, KS-2/KS-3 use only [ks2Prices], not global supplier catalog.
  bool useProjectPricesOnly;

  /// When true, KS-2 export blocked if any line lacks a unit price.
  bool requireFullKs2Pricing;

  /// Registered intermediate KS-2 acts (project-level, per scope).
  List<Ks2ActRecord> ks2Acts;

  /// Contract work types on this object: floor, walls, ceiling (any subset).
  List<String> enabledWorkScopes;

  ProjectStage stage;

  /// Auto-increment for hidden-works / KS-2 acts (per project).
  int nextActNumber;

  /// Preferred supplier catalog for pricing (falls back to first listed).
  int? primarySupplierId;

  /// КП / КС-2 / акт — line mode, price per m², form style.
  ContractDocumentSettings contractDocs;

  int allocateActNumber() => nextActNumber++;

  Map<String, dynamic> toJson() => {
        'stamp': stamp.toJson(),
        'contract': contract.toJson(),
        if (vedomostTemplatePath != null) 'vedomost_template_path': vedomostTemplatePath,
        if (ks2TemplatePath != null) 'ks2_template_path': ks2TemplatePath,
        if (ks3TemplatePath != null) 'ks3_template_path': ks3TemplatePath,
        if (actHiddenTemplatePath != null) 'act_hidden_template_path': actHiddenTemplatePath,
        'certificates': certificates.map((c) => c.toJson()).toList(),
        if (ks2Prices.isNotEmpty)
          'ks2_prices': ks2Prices.map((p) => p.toJson()).toList(),
        if (useProjectPricesOnly) 'use_project_prices_only': true,
        if (requireFullKs2Pricing) 'require_full_ks2_pricing': true,
        if (ks2Acts.isNotEmpty)
          'ks2_acts': ks2Acts.map((a) => a.toJson()).toList(),
        if (enabledWorkScopes.length != 3 ||
            !enabledWorkScopes.contains('floor') ||
            !enabledWorkScopes.contains('walls') ||
            !enabledWorkScopes.contains('ceiling'))
          'enabled_work_scopes': enabledWorkScopes,
        'stage': stage.name,
        'next_act_number': nextActNumber,
        if (primarySupplierId != null) 'primary_supplier_id': primarySupplierId,
        'contract_docs': contractDocs.toJson(),
        if (vault.isNotEmpty) 'vault': vault.map((e) => e.toJson()).toList(),
      };

  static ProjectDocumentation fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return ProjectDocumentation();
    final certsRaw = json['certificates'] as List? ?? [];
    final pricesRaw = json['ks2_prices'] as List? ?? [];
    final actsRaw = json['ks2_acts'] as List? ?? [];
    final vaultRaw = json['vault'] as List? ?? [];
    return ProjectDocumentation(
      stamp: DocumentationStamp.fromJson(
        json['stamp'] is Map ? Map<String, dynamic>.from(json['stamp'] as Map) : null,
      ),
      contract: ProjectContractInfo.fromJson(
        json['contract'] is Map ? Map<String, dynamic>.from(json['contract'] as Map) : null,
      ),
      vedomostTemplatePath: json['vedomost_template_path'] as String?,
      ks2TemplatePath: json['ks2_template_path'] as String?,
      ks3TemplatePath: json['ks3_template_path'] as String?,
      actHiddenTemplatePath: json['act_hidden_template_path'] as String?,
      certificates: certsRaw
          .map((e) => MaterialCertificate.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      ks2Prices: pricesRaw
          .map((e) => ProjectPriceLine.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      ks2Acts: actsRaw
          .map((e) => Ks2ActRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((a) => a.id.isNotEmpty)
          .toList(),
      enabledWorkScopes: (json['enabled_work_scopes'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['floor', 'walls', 'ceiling'],
      useProjectPricesOnly: json['use_project_prices_only'] as bool? ?? false,
      requireFullKs2Pricing: json['require_full_ks2_pricing'] as bool? ?? false,
      stage: ProjectStage.parse(json['stage'] as String?),
      nextActNumber: (json['next_act_number'] as num?)?.toInt() ?? 1,
      primarySupplierId: (json['primary_supplier_id'] as num?)?.toInt(),
      contractDocs: ContractDocumentSettings.fromJson(
        json['contract_docs'] is Map
            ? Map<String, dynamic>.from(json['contract_docs'] as Map)
            : null,
      ),
      vault: vaultRaw
          .map((e) => ProjectVaultEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((e) => e.id.isNotEmpty)
          .toList(),
    );
  }
}
