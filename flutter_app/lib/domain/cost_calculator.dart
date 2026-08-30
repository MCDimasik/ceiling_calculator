import 'dart:math' as math;

import 'material_catalog.dart';
import 'models.dart';
import 'project_materials.dart';

class SupplierPrice {
  SupplierPrice({
    required this.itemKey,
    required this.productName,
    this.unitPriceCost = 0,
    this.unitPriceClient = 0,
    this.receiptUnit = 'piece',
    this.unitsPerPack = 1,
  });

  final String itemKey;
  String productName;
  double unitPriceCost;
  double unitPriceClient;
  String receiptUnit;
  double unitsPerPack;

  String get calcMatchKey =>
      catalogByItemKey(itemKey)?.calcMatchKey ?? productName;
}

class Supplier {
  Supplier({required this.name, this.id, DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();

  int? id;
  String name;
  DateTime createdAt;
}

class CostLine {
  CostLine({
    required this.name,
    required this.calcKey,
    required this.qty,
    required this.billQty,
    required this.billUnit,
    required this.hasPrice,
    this.unitPrice,
    this.lineTotal,
  });

  final String name;
  final String calcKey;
  final int qty;
  final int billQty;
  final String billUnit;
  final bool hasPrice;
  final double? unitPrice;
  final double? lineTotal;
}

class ProjectCostResult {
  ProjectCostResult({
    required this.areaM2,
    required this.perimeterM,
    required this.lines,
    required this.total,
    required this.totalCost,
    required this.benefit,
    required this.missingCount,
  });

  final double areaM2;
  final double perimeterM;
  final List<CostLine> lines;
  final double total;
  final double totalCost;
  final double? benefit;
  final int missingCount;
}

bool billsByPack(String receiptUnit, double unitsPerPack) {
  final upp = unitsPerPack <= 0 ? 1.0 : unitsPerPack;
  return upp > 1;
}

(int billQty, String billUnit) qtyToBillUnits(
  int qtyPieces,
  String receiptUnit,
  double unitsPerPack,
) {
  if (qtyPieces <= 0) return (0, 'шт');
  if (billsByPack(receiptUnit, unitsPerPack)) {
    final upp = math.max(1, unitsPerPack.round());
    return ((qtyPieces / upp).ceil(), 'уп');
  }
  return (qtyPieces, 'шт');
}

double unitPriceForBilling(double piecePrice, String receiptUnit, double unitsPerPack) {
  if (piecePrice <= 0) return 0;
  if (billsByPack(receiptUnit, unitsPerPack)) {
    return double.parse((piecePrice * unitsPerPack).toStringAsFixed(2));
  }
  return piecePrice;
}

ProjectCostResult calculateProjectCost(
  Project project,
  Map<String, SupplierPrice> pricesByCalcKey,
) {
  final (totals, area, peri) = aggregateProjectTotals(project);
  final lines = <CostLine>[];
  var totalClient = 0.0;
  var totalCost = 0.0;
  var missing = 0;

  final keys = totals.keys.toList()..sort();
  for (final key in keys) {
    final qty = totals[key]!;
    final info = pricesByCalcKey[key];
    final hasClient = info != null && info.unitPriceClient > 0;
    final hasCost = info != null && info.unitPriceCost > 0;

    var receiptUnit = 'piece';
    var upp = 1.0;
    if (hasClient) {
      receiptUnit = info.receiptUnit;
      upp = info.unitsPerPack;
    }

    if (hasClient) {
      final (billQty, billUnit) = qtyToBillUnits(qty, receiptUnit, upp);
      final unitBill = unitPriceForBilling(info.unitPriceClient, receiptUnit, upp);
      final lineTotal = billQty * unitBill;
      totalClient += lineTotal;
      lines.add(CostLine(
        name: info.productName,
        calcKey: key,
        qty: qty,
        billQty: billQty,
        billUnit: billUnit,
        hasPrice: true,
        unitPrice: unitBill,
        lineTotal: lineTotal,
      ));
    } else {
      missing++;
      lines.add(CostLine(
        name: key,
        calcKey: key,
        qty: qty,
        billQty: qty,
        billUnit: 'шт',
        hasPrice: false,
      ));
    }

    if (hasCost) {
      final ru = info.receiptUnit;
      final u = info.unitsPerPack;
      final (billQty, _) = qtyToBillUnits(qty, ru, u);
      final unitBill = unitPriceForBilling(info.unitPriceCost, ru, u);
      totalCost += billQty * unitBill;
    }
  }

  return ProjectCostResult(
    areaM2: area,
    perimeterM: peri,
    lines: lines,
    total: totalClient,
    totalCost: totalCost,
    benefit: totalCost > 0 ? totalClient - totalCost : null,
    missingCount: missing,
  );
}
