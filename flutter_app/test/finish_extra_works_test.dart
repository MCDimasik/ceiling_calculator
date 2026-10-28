import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/finish_extra_works.dart';
import 'package:ceiling_calculator/domain/finish_vedomost.dart';
import 'package:ceiling_calculator/domain/models.dart';

void main() {
  test('measure area with waste', () {
    final work = FinishExtraWork(
      id: '1',
      title: 'Плитка',
      unit: FinishWorkUnit.m2,
      qtyMode: FinishWorkQtyMode.measure,
      wastePercent: 10,
      measure: const FinishWorkMeasure(
        kind: FinishMeasureKind.area,
        lengthM: 2,
        widthM: 1.5,
      ),
    );
    expect(work.baseQuantity, closeTo(3.0, 1e-9));
    expect(work.quantityWithWaste, closeTo(3.3, 1e-9));
  });

  test('manual qty with waste', () {
    final work = FinishExtraWork(
      id: '2',
      title: 'Комплект',
      unit: FinishWorkUnit.set,
      qtyMode: FinishWorkQtyMode.manual,
      manualQty: 4,
      wastePercent: 25,
    );
    expect(work.quantityWithWaste, closeTo(5.0, 1e-9));
  });

  test('round-trip encode state', () {
    final state = FinishExtraWorksState(
      works: [
        FinishExtraWork(
          id: 'a',
          title: 'Перила',
          category: 'металлоконструкции',
          unit: FinishWorkUnit.m,
          qtyMode: FinishWorkQtyMode.measure,
          wastePercent: 5,
          measure: const FinishWorkMeasure(
            kind: FinishMeasureKind.length,
            lengthM: 12.5,
          ),
        ),
      ],
      templates: [
        FinishWorkTemplate(
          id: 'custom',
          title: 'Мой шаблон',
          unit: FinishWorkUnit.pcs,
        ),
      ],
    );
    final decoded = FinishExtraWorksState.decode(state.encode());
    expect(decoded.works, hasLength(1));
    expect(decoded.works.first.title, 'Перила');
    expect(decoded.works.first.baseQuantity, closeTo(12.5, 1e-9));
    expect(decoded.templates, hasLength(1));
    expect(decoded.allTemplates.any((t) => t.id == 'seed_outdoor_tile'), isTrue);
    expect(decoded.allTemplates.any((t) => t.id == 'custom'), isTrue);
  });

  test('aggregate vedomost includes project extra works', () {
    final walls = [
      [0.0, 0.0, 400.0, 0.0],
      [400.0, 0.0, 400.0, 300.0],
      [400.0, 300.0, 0.0, 300.0],
      [0.0, 300.0, 0.0, 0.0],
    ];
    final room = Room(id: 1, name: 'R', walls: walls);
    final state = FinishExtraWorksState(
      works: [
        FinishExtraWork(
          id: 'x',
          title: 'Крыльцо',
          category: 'улица',
          unit: FinishWorkUnit.m2,
          qtyMode: FinishWorkQtyMode.manual,
          manualQty: 8,
          wastePercent: 10,
        ),
      ],
    );
    final project = Project(
      name: 'P',
      rooms: [room],
      finishExtraWorksJson: state.toJson(),
    );
    final lines = aggregateFinishVedomostLines(project);
    expect(lines.any((l) => l.section == 'Другие работы'), isTrue);
    expect(
      lines.any((l) => l.name.contains('Крыльцо') && l.quantity == '8.80'),
      isTrue,
    );
    // Finish BOM is not only ceiling guide SKUs.
    expect(lines.any((l) => l.section == 'Пол' || l.section == 'Потолок'), isTrue);
    expect(lines.every((l) => !l.name.startsWith('Направляющая')), isTrue);
  });
}
