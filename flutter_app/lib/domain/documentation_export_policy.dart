import 'contract_document_model.dart';
import 'cost_calculator.dart';
import 'documentation_model.dart';
import 'ks2_work_scope.dart';
import 'models.dart';
import 'room_finish_areas.dart';
import 'special_space.dart';
import 'work_rates_catalog.dart';

/// Whether exports are allowed at the current project stage.
///
/// Stage gate removed: UI uses room workflow «В работе / Сдан», not
/// design→install. Kept as always-allow for backward-compatible call sites.
(String? blockReason, bool allowed) documentationExportPolicy(ProjectDocumentation doc) {
  return (null, true);
}

class ExportReadinessReport {
  const ExportReadinessReport({
    this.blockers = const [],
    this.warnings = const [],
  });

  final List<String> blockers;
  final List<String> warnings;

  bool get canProceed => blockers.isEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
}

/// Pre-export checks: stage, stamp, price coverage.
ExportReadinessReport checkExportReadiness({
  required Project project,
  required Room room,
  required ProjectDocumentation doc,
  required RoomDocumentationChecklist checklist,
  Map<String, SupplierPrice>? supplierPrices,
  bool forKs2 = false,
  WorkScope? scope,
  List<WorkScope>? scopes,
}) {
  final blockers = <String>[];
  final warnings = <String>[];

  // KS-2 closure is gated by layout/scope, not by project stage «Проектирование».
  if (!forKs2) {
    final (stageReason, stageOk) = documentationExportPolicy(doc);
    if (!stageOk && stageReason != null) blockers.add(stageReason);
  }

  if (!roomHasPlanOrSchematic(room)) {
    blockers.add(room.isSpecialSpace
        ? 'Нет схемы / параметров специального помещения'
        : 'Нет чертежа помещения');
  }

  final stamp = doc.stamp.withDefaults(projectName: project.name, roomName: room.name);
  if (stamp.customer.isEmpty) warnings.add('Не заполнен заказчик');
  if (stamp.executor.isEmpty) warnings.add('Не заполнен исполнитель');
  if (doc.contract.contractNumber.isEmpty) warnings.add('Не указан № договора');

  if (forKs2) {
    final checkScopes = scopes ?? (scope != null ? [scope] : WorkScope.values);
    for (final sc in checkScopes) {
      final coverage = ks2PriceCoverage(
        project: project,
        room: room,
        supplierPrices: supplierPrices,
        scope: sc,
      );
      if (coverage.totalRows == 0) continue;
      if (doc.requireFullKs2Pricing && coverage.missingCount > 0) {
        blockers.add(
          'КС-2 (${sc.labelRu}): не хватает расценок (${coverage.missingCount} из ${coverage.totalRows})',
        );
      } else if (coverage.missingCount > 0) {
        warnings.add(
          'КС-2 (${sc.labelRu}): ${coverage.missingCount} из ${coverage.totalRows} строк без расценки',
        );
      }
    }
  }

  return ExportReadinessReport(blockers: blockers, warnings: warnings);
}

class Ks2PriceCoverage {
  const Ks2PriceCoverage({
    required this.totalRows,
    required this.pricedRows,
    required this.missingCount,
    required this.missingNames,
  });

  final int totalRows;
  final int pricedRows;
  final int missingCount;
  final List<String> missingNames;
}

/// Coverage against smeta work lines (room×scope), not material vedomost.
Ks2PriceCoverage ks2PriceCoverage({
  required Project project,
  required Room room,
  Map<String, SupplierPrice>? supplierPrices,
  WorkScope? scope,
}) {
  final doc = ProjectDocumentation.fromJson(project.documentationJson);
  final scopeId = switch (scope) {
    WorkScope.floor => 'floor',
    WorkScope.walls => 'walls',
    WorkScope.ceiling => 'ceiling',
    null => null,
  };
  final scopeIds = scopeId != null
      ? {scopeId}
      : {'floor', 'walls', 'ceiling'};

  final lines = buildScopedContractWorkLines(
    settings: doc.contractDocs,
    rooms: [room],
    floors: project.floors,
    scopeIds: scopeIds,
    catalog: WorkRatesCatalogStore.peek(),
    supplierPrices: supplierPrices,
  );

  if (lines.isEmpty) {
    return const Ks2PriceCoverage(
      totalRows: 0,
      pricedRows: 0,
      missingCount: 0,
      missingNames: [],
    );
  }

  final missing = <String>[];
  var priced = 0;
  for (final line in lines) {
    if (line.quantity <= 0) continue;
    if (line.unitPrice > 0) {
      priced++;
    } else {
      missing.add(line.name);
    }
  }
  return Ks2PriceCoverage(
    totalRows: priced + missing.length,
    pricedRows: priced,
    missingCount: missing.length,
    missingNames: missing,
  );
}
