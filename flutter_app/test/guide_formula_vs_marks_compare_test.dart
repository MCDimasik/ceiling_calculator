import 'package:ceiling_calculator/domain/ceiling_guides.dart';
import 'package:ceiling_calculator/domain/materials_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

List<List<double>> rect(double w, double h) => [
      [0, 0, w, 0],
      [w, 0, w, h],
      [w, h, 0, h],
      [0, h, 0, 0],
    ];

Map<String, int> formulaGuides(List<List<double>> walls, {bool classic = false}) {
  final area = MaterialsCalculator.roomAreaM2(walls);
  if (classic) {
    return {
      'Направляющая 2400': ((area * 0.84) / 2.4).ceil(),
      'Направляющая 1200': ((area * 1.68) / 1.2).ceil(),
      'Направляющая 600': ((area * 0.85) / 0.6).ceil(),
    };
  }
  return {
    'Направляющая 3600': ((area * 0.84) / 3.6).ceil(),
    'Направляющая 1200': ((area * 1.68) / 1.2).ceil(),
    'Направляющая 600': ((area * 0.85) / 0.6).ceil(),
  };
}

Map<String, int> marksGuides(
  List<List<double>> walls, {
  required CeilingFrameTemplate template,
  double offsetX = 0,
  double offsetY = 0,
  double cell = 60,
}) {
  final seed = CeilingGuideMark(
    axis: GuideAxis.horizontal,
    lineIndex: 0,
    kind: template.mainGuideKind,
    anchorAlongIndex: 0,
  );
  final marks = proposeCeilingFrame(
    template: template,
    seed: seed,
    offsetX: offsetX,
    offsetY: offsetY,
    cellSize: cell,
    walls: walls,
  );
  return countGuidesFromMarks(
        marks,
        walls,
        offsetX: offsetX,
        offsetY: offsetY,
        cellSize: cell,
      ) ??
      {};
}

String fmtDelta(int marks, int formula) {
  final d = marks - formula;
  final pct = formula == 0 ? (marks == 0 ? 0.0 : 100.0) : (d / formula * 100);
  final sign = d > 0 ? '+' : '';
  return '$marks vs $formula ($sign$d, ${sign}${pct.toStringAsFixed(0)}%)';
}

void main() {
  test('compare formula vs full guide frame', () {
    final sizes = <(double, double, String)>[
      (300, 300, '3×3 м'),
      (400, 300, '4×3 м'),
      (600, 400, '6×4 м'),
      (800, 600, '8×6 м'),
      (1200, 600, '12×6 м'),
      (1000, 1000, '10×10 м'),
      (1500, 800, '15×8 м'),
    ];

    final buf = StringBuffer();
    buf.writeln('=== Armstrong / GL: метки (полный каркас) vs формула ===');
    buf.writeln('Комната | S м² | 3600 | 1200 | 600');

    final sumPct = <String, List<double>>{
      '3600': [],
      '1200': [],
      '600': [],
    };

    for (final (w, h, label) in sizes) {
      final walls = rect(w, h);
      final area = MaterialsCalculator.roomAreaM2(walls);
      final f = formulaGuides(walls);
      final m = marksGuides(walls, template: CeilingFrameTemplate.armstrong);
      for (final key in ['Направляющая 3600', 'Направляющая 1200', 'Направляющая 600']) {
        final short = key.split(' ').last;
        final mv = m[key] ?? 0;
        final fv = f[key] ?? 0;
        final pct = fv == 0 ? 0.0 : ((mv - fv) / fv * 100);
        sumPct[short]!.add(pct);
      }
      buf.writeln(
        '$label | ${area.toStringAsFixed(1)} | '
        '${fmtDelta(m['Направляющая 3600'] ?? 0, f['Направляющая 3600'] ?? 0)} | '
        '${fmtDelta(m['Направляющая 1200'] ?? 0, f['Направляющая 1200'] ?? 0)} | '
        '${fmtDelta(m['Направляющая 600'] ?? 0, f['Направляющая 600'] ?? 0)}',
      );
    }

    buf.writeln('');
    buf.writeln('Средний сдвиг меток относительно формулы (Armstrong):');
    for (final e in sumPct.entries) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      final sign = avg > 0 ? '+' : '';
      buf.writeln('  ${e.key}: ${sign}${avg.toStringAsFixed(0)}%');
    }

    buf.writeln('');
    buf.writeln('=== Грильято classic: метки vs формула (несущие 2400) ===');
    for (final (w, h, label) in sizes.take(4)) {
      final walls = rect(w, h);
      final area = MaterialsCalculator.roomAreaM2(walls);
      final f = formulaGuides(walls, classic: true);
      final m = marksGuides(walls, template: CeilingFrameTemplate.grilyatoClassic);
      buf.writeln(
        '$label | ${area.toStringAsFixed(1)} | '
        '${fmtDelta(m['Направляющая 2400'] ?? 0, f['Направляющая 2400'] ?? 0)} | '
        '${fmtDelta(m['Направляющая 1200'] ?? 0, f['Направляющая 1200'] ?? 0)} | '
        '${fmtDelta(m['Направляющая 600'] ?? 0, f['Направляющая 600'] ?? 0)}',
      );
    }

    // Also: offset shift effect on one room
    buf.writeln('');
    buf.writeln('=== Смещение сетки 4×3 м (Armstrong), метки vs формула ===');
    final walls = rect(400, 300);
    final f = formulaGuides(walls);
    for (final ox in [0.0, 15.0, 30.0, 45.0]) {
      final m = marksGuides(
        walls,
        template: CeilingFrameTemplate.armstrong,
        offsetX: ox,
        offsetY: ox,
      );
      buf.writeln(
        'offset ${ox.toStringAsFixed(0)}: '
        '${fmtDelta(m['Направляющая 3600'] ?? 0, f['Направляющая 3600'] ?? 0)} | '
        '${fmtDelta(m['Направляющая 1200'] ?? 0, f['Направляющая 1200'] ?? 0)} | '
        '${fmtDelta(m['Направляющая 600'] ?? 0, f['Направляющая 600'] ?? 0)}',
      );
    }

    // ignore: avoid_print
    print(buf.toString());
    expect(true, isTrue);
  });
}
