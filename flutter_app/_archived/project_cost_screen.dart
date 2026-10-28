import 'package:flutter/material.dart';

import 'widgets/screen_scaffold.dart';

import '../app_scope.dart';
import '../domain/cost_calculator.dart';
import '../domain/documentation_model.dart';
import '../domain/models.dart';
import '../domain/money_format.dart';
import '../domain/primary_supplier.dart';

class ProjectCostScreen extends StatefulWidget {
  const ProjectCostScreen({super.key, required this.projectId});

  final int projectId;

  @override
  State<ProjectCostScreen> createState() => _ProjectCostScreenState();
}

class _ProjectCostScreenState extends State<ProjectCostScreen> {
  Project? _project;
  List<Supplier> _suppliers = [];
  int? _supplierId;
  ProjectCostResult? _result;
  bool _loading = true;
  bool _showBenefit = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  Future<void> _load() async {
    final scope = AppScope.of(context);
    final project = await scope.projects.getProject(widget.projectId);
    final suppliers = await scope.suppliers.listSuppliers();
    final doc = ProjectDocumentation.fromJson(project?.documentationJson);
    if (!mounted) return;
    setState(() {
      _project = project;
      _suppliers = suppliers;
      _supplierId = resolvePrimarySupplierId(doc, suppliers);
      _loading = false;
    });
    await _recalc();
  }

  Future<void> _recalc() async {
    final project = _project;
    final sid = _supplierId;
    if (project == null || sid == null) {
      setState(() => _result = null);
      return;
    }
    final prices = await AppScope.of(context).suppliers.pricesByCalcMatchKey(sid);
    final result = calculateProjectCost(project, prices);
    if (!mounted) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));
    }

    final r = _result;
    return ScreenScaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () => setState(() => _showBenefit = !_showBenefit),
          child: Text('Стоимость / ${_project?.name ?? ''}'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_suppliers.isEmpty)
            const Text('Сначала создайте поставщика')
          else
            DropdownButtonFormField<int>(
              value: _supplierId,
              decoration: const InputDecoration(
                labelText: 'Поставщик',
                border: OutlineInputBorder(),
              ),
              items: _suppliers
                  .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                  .toList(),
              onChanged: (v) async {
                setState(() => _supplierId = v);
                await _recalc();
              },
            ),
          if (r != null) ...[
            const SizedBox(height: 12),
            Text(
              'Площадь ${r.areaM2.toStringAsFixed(2)} м² · периметр ${r.perimeterM.toStringAsFixed(2)} м',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final line in r.lines)
              ListTile(
                dense: true,
                title: Text(
                  line.name,
                  style: TextStyle(
                    fontWeight: line.hasPrice ? FontWeight.w600 : FontWeight.normal,
                    color: line.hasPrice ? null : Theme.of(context).colorScheme.error,
                  ),
                ),
                subtitle: Text(
                  line.hasPrice
                      ? '${line.qty} шт → ${line.billQty} ${line.billUnit} × ${line.unitPrice!.toStringAsFixed(2)}'
                      : 'нет цены · ${line.qty} шт',
                ),
                trailing: Text(
                  line.lineTotal != null ? formatMoney(line.lineTotal!, fractionDigits: 2) : '—',
                ),
              ),
            const Divider(),
            ListTile(
              title: const Text('Итого'),
              trailing: Text(
                formatMoney(r.total, fractionDigits: 2),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            if (_showBenefit && r.benefit != null)
              ListTile(
                title: const Text('Выгода'),
                subtitle: Text('Закуп ${formatMoney(r.totalCost, fractionDigits: 2)}'),
                trailing: Text(
                  formatMoney(r.benefit!, fractionDigits: 2),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (r.missingCount > 0)
              Text(
                'Без цены: ${r.missingCount}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            Text(
              'Удержите заголовок, чтобы показать «Выгода»',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
