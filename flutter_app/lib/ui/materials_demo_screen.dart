import 'package:flutter/material.dart';

import '../domain/materials_calculator.dart';

class MaterialsDemoScreen extends StatefulWidget {
  const MaterialsDemoScreen({super.key});

  @override
  State<MaterialsDemoScreen> createState() => _MaterialsDemoScreenState();
}

class _MaterialsDemoScreenState extends State<MaterialsDemoScreen> {
  CeilingType _type = CeilingType.armstrong;
  String _cell = '100x100';
  // 4×3 m room in cm walls
  final _walls = <List<double>>[
    [0, 0, 400, 0],
    [400, 0, 400, 300],
    [400, 300, 0, 300],
    [0, 300, 0, 0],
  ];

  @override
  Widget build(BuildContext context) {
    final area = MaterialsCalculator.roomAreaM2(_walls);
    final result = MaterialsCalculator.calculate(
      type: _type,
      walls: _walls,
      cassetteCount: 34,
      cellSize: _cell,
      lightCount: 2,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Материалы')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Комната 4×3 м, S = ${area.toStringAsFixed(2)} м², кассеты=34, свет=2'),
          const SizedBox(height: 12),
          SegmentedButton<CeilingType>(
            segments: const [
              ButtonSegment(value: CeilingType.armstrong, label: Text('Армстронг')),
              ButtonSegment(value: CeilingType.grilyatoGl, label: Text('GL')),
              ButtonSegment(value: CeilingType.grilyatoClassic, label: Text('Грильято')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          if (_type != CeilingType.armstrong) ...[
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '50x50', label: Text('50')),
                ButtonSegment(value: '75x75', label: Text('75')),
                ButtonSegment(value: '100x100', label: Text('100')),
              ],
              selected: {_cell},
              onSelectionChanged: (s) => setState(() => _cell = s.first),
            ),
          ],
          const SizedBox(height: 16),
          ...result.entries.map(
            (e) => ListTile(
              dense: true,
              title: Text(e.key),
              trailing: Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
