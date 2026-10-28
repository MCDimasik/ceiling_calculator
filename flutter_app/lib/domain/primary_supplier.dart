import '../data/supplier_repository.dart';
import 'cost_calculator.dart';
import 'documentation_model.dart';

/// Pick primary supplier id from project doc, falling back to first listed.
int? resolvePrimarySupplierId(ProjectDocumentation doc, List<Supplier> suppliers) {
  if (suppliers.isEmpty) return null;
  final preferred = doc.primarySupplierId;
  if (preferred != null) {
    for (final s in suppliers) {
      if (s.id == preferred) return preferred;
    }
  }
  return suppliers.first.id;
}

/// Load calc-match prices for the project's primary (or first) supplier.
Future<Map<String, SupplierPrice>?> loadPrimarySupplierPrices({
  required SupplierRepository repo,
  required ProjectDocumentation doc,
}) async {
  final suppliers = await repo.listSuppliers();
  final id = resolvePrimarySupplierId(doc, suppliers);
  if (id == null) return null;
  return repo.pricesByCalcMatchKey(id);
}

Supplier? findSupplierById(List<Supplier> suppliers, int? id) {
  if (id == null) return null;
  for (final s in suppliers) {
    if (s.id == id) return s;
  }
  return null;
}
