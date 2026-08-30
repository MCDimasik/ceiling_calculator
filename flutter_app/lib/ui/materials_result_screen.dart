import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../domain/materials_calculator.dart';
import '../domain/materials_formulas.dart';
import '../domain/models.dart';
import '../domain/project_materials.dart';
import 'layout_screen.dart';
import 'project_cost_screen.dart';

class MaterialsResultScreen extends StatefulWidget {
  const MaterialsResultScreen({
    super.key,
    required this.projectId,
    this.roomId,
  });

  final int projectId;
  final int? roomId;

  @override
  State<MaterialsResultScreen> createState() => _MaterialsResultScreenState();
}

class _MaterialsResultScreenState extends State<MaterialsResultScreen> {
  Project? _project;
  Room? _room;
  Map<String, int> _result = {};
  bool _loading = true;
  bool _showFormulas = false;

  String _ceiling = 'Армстронг';
  String _susp = 'Подвес 0,5';
  String _cell = '50x50';
  bool _override = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final project = await AppScope.of(context).projects.getProject(widget.projectId);
    Room? room;
    if (project != null && widget.roomId != null) {
      for (final r in project.rooms) {
        if (r.id == widget.roomId) room = r;
      }
    }
    if (!mounted) return;
    setState(() {
      _project = project;
      _room = room;
      if (room != null && project != null) {
        final cfg = roomEffectiveConfig(room, project);
        _ceiling = cfg.$1;
        _susp = cfg.$2;
        _cell = cfg.$3;
        _override = room.materialsOverride;
      } else if (project != null) {
        _ceiling = project.materialsCeiling ?? 'Армстронг';
        _susp = project.materialsSusp ?? 'Подвес 0,5';
        _cell = project.materialsCell ?? '50x50';
      }
      _recalc();
      _loading = false;
    });
  }

  void _recalc() {
    final project = _project;
    if (project == null) {
      _result = {};
      return;
    }
    if (_room != null) {
      _room!
        ..materialsOverride = _override
        ..materialsCeiling = _ceiling
        ..materialsSusp = _susp
        ..materialsCell = _cell;
      _result = calculateRoomMaterials(_room!, project);
    } else {
      project.materialsCeiling = _ceiling;
      project.materialsSusp = _susp;
      project.materialsCell = _cell;
      final (totals, _, _) = aggregateProjectTotals(project);
      _result = totals;
    }
  }

  Future<void> _saveConfig() async {
    final project = _project;
    if (project == null) return;
    final repo = AppScope.of(context).projects;
    if (_room != null) {
      await repo.updateRoomMaterials(
        _room!.id!,
        override: _override,
        ceiling: _ceiling,
        susp: _susp,
        cell: _cell,
      );
    } else {
      await repo.updateProjectMaterials(
        project.id!,
        ceiling: _ceiling,
        susp: _susp,
        cell: _cell,
      );
    }
  }

  Future<void> _copy() async {
    final buf = StringBuffer();
    for (final e in (_result.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
      buf.writeln('${e.key}: ${e.value}');
    }
    final text = buf.toString();
    await Clipboard.setData(ClipboardData(text: text));
    await SharePlus.instance.share(ShareParams(text: text, subject: 'Материалы'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Скопировано / поделиться')),
    );
  }

  Future<void> _persistSilent() async {
    await _saveConfig();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final title = _room?.name ?? _project?.name ?? 'Материалы';
    final needsCell = _ceiling == 'Грильято' || _ceiling == 'GL';
    final admin = AppScope.of(context).admin.unlocked;
    final isProjectLevel = widget.roomId == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (isProjectLevel && admin)
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProjectCostScreen(projectId: widget.projectId),
                  ),
                );
              },
              child: const Text('Стоимость'),
            ),
          if (_room != null)
            TextButton(
              onPressed: () async {
                await _persistSilent();
                if (!mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LayoutScreen(
                      projectId: widget.projectId,
                      roomId: widget.roomId!,
                    ),
                  ),
                );
                await _load();
              },
              child: const Text('Раскладка'),
            ),
          IconButton(onPressed: _copy, tooltip: 'Поделиться', icon: const Icon(Icons.share)),
          IconButton(
            tooltip: 'Сохранить настройки',
            onPressed: () async {
              await _saveConfig();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Настройки сохранены')),
                );
              }
            },
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_room != null)
            SwitchListTile(
              title: const Text('Индивидуальная конфигурация'),
              value: _override,
              onChanged: (v) => setState(() {
                _override = v;
                _recalc();
                _persistSilent();
              }),
            ),
          Text('Тип потолка', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'Армстронг', label: Text('Армстронг')),
              ButtonSegment(value: 'Грильято', label: Text('Грильято')),
              ButtonSegment(value: 'GL', label: Text('GL')),
            ],
            selected: {_ceiling},
            onSelectionChanged: (s) => setState(() {
              _ceiling = s.first;
              // Kivy parity: reset under-ceiling defaults when type changes.
              _susp = 'Подвес 0,5';
              _cell = '50x50';
              _recalc();
              _persistSilent();
            }),
          ),
          const SizedBox(height: 12),
          Text('Подвес', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'Подвес 0,5', label: Text('0,5')),
              ButtonSegment(value: 'Подвес 1', label: Text('1')),
              ButtonSegment(value: 'Подвес 1,5', label: Text('1,5')),
            ],
            selected: {_susp},
            onSelectionChanged: (s) => setState(() {
              _susp = s.first;
              _recalc();
              _persistSilent();
            }),
          ),
          if (needsCell) ...[
            const SizedBox(height: 12),
            Text('Ячейка', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: '50x50', label: Text('50×50')),
                ButtonSegment(value: '75x75', label: Text('75×75')),
                ButtonSegment(value: '100x100', label: Text('100×100')),
              ],
              selected: {_cell},
              onSelectionChanged: (s) => setState(() {
                _cell = s.first;
                _recalc();
                _persistSilent();
              }),
            ),
          ],
          const SizedBox(height: 12),
          Text('Результат', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_result.isEmpty)
            const Text('Нет данных — нарисуйте стены комнаты')
          else
            ...(_result.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
                .map(
              (e) => ListTile(
                dense: true,
                title: Text(e.key),
                trailing: Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          TextButton(
            onPressed: () => setState(() => _showFormulas = !_showFormulas),
            child: Text(_showFormulas ? 'Скрыть формулы' : 'Показать формулы'),
          ),
          if (_showFormulas) ...[
            const SizedBox(height: 8),
            SelectableText(
              materialsFormulasText(
                ceilingLabel: _ceiling,
                areaM2: _room != null
                    ? MaterialsCalculator.roomAreaM2(_room!.walls)
                    : (_project?.rooms.fold<double>(
                          0,
                          (a, r) => a + MaterialsCalculator.roomAreaM2(r.walls),
                        ) ??
                        0),
                perimeterM: _room != null
                    ? MaterialsCalculator.roomPerimeterCm(_room!.walls) / 100
                    : (_project?.rooms.fold<double>(
                          0,
                          (a, r) => a + MaterialsCalculator.roomPerimeterCm(r.walls) / 100,
                        ) ??
                        0),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
