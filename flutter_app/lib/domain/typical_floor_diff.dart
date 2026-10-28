import 'materials_calculator.dart';
import 'models.dart';
import 'project_materials.dart';

class TypicalFloorDiffLine {
  const TypicalFloorDiffLine({
    required this.name,
    required this.templateQty,
    required this.copiesQty,
  });

  final String name;
  final int templateQty;
  final int copiesQty;

  int get delta => copiesQty - templateQty;
  bool get hasDelta => delta != 0;
}

class TypicalFloorDiff {
  const TypicalFloorDiff({
    required this.templateName,
    required this.copyCount,
    required this.templateAreaM2,
    required this.copiesAreaM2,
    required this.materialLines,
  });

  final String templateName;
  final int copyCount;
  final double templateAreaM2;
  final double copiesAreaM2;
  final List<TypicalFloorDiffLine> materialLines;

  double get areaDeltaM2 => copiesAreaM2 - templateAreaM2 * copyCount;
  bool get hasMaterialDelta => materialLines.any((l) => l.hasDelta);
}

TypicalFloorDiff compareTypicalFloor({
  required Room template,
  required Project project,
  required List<Room> copies,
}) {
  final templateMat = calculateRoomMaterials(template, project);
  final copyCount = copies.length;
  var copiesArea = 0.0;
  final agg = <String, int>{};

  for (final c in copies) {
    copiesArea += MaterialsCalculator.roomAreaM2(c.walls);
    final m = calculateRoomMaterials(c, project);
    for (final e in m.entries) {
      agg[e.key] = (agg[e.key] ?? 0) + e.value;
    }
  }

  final templateArea = MaterialsCalculator.roomAreaM2(template.walls);
  final keys = {...templateMat.keys, ...agg.keys};
  final lines = <TypicalFloorDiffLine>[];
  for (final k in keys) {
    final tQty = templateMat[k] ?? 0;
    final cQty = agg[k] ?? 0;
    if (tQty == 0 && cQty == 0) continue;
    lines.add(TypicalFloorDiffLine(name: k, templateQty: tQty, copiesQty: cQty));
  }
  lines.sort((a, b) => a.name.compareTo(b.name));

  return TypicalFloorDiff(
    templateName: template.name,
    copyCount: copyCount,
    templateAreaM2: templateArea,
    copiesAreaM2: copiesArea,
    materialLines: lines,
  );
}

String formatTypicalFloorDiffText(TypicalFloorDiff diff) {
  final buf = StringBuffer()
    ..writeln('Сравнение типового этажа · «${diff.templateName}»')
    ..writeln('Копий: ${diff.copyCount}')
    ..writeln(
      'Площадь шаблона: ${diff.templateAreaM2.toStringAsFixed(2)} м² · '
      'копии: ${diff.copiesAreaM2.toStringAsFixed(2)} м² · '
      'Δ: ${diff.areaDeltaM2.toStringAsFixed(2)} м²',
    );
  final deltas = diff.materialLines.where((l) => l.hasDelta).toList();
  if (deltas.isEmpty) {
    buf.writeln('Материалы: расхождений нет');
  } else {
    buf.writeln('Расхождения материалов:');
    for (final l in deltas) {
      buf.writeln('• ${l.name}: шаблон ${l.templateQty} → копии ${l.copiesQty} (Δ ${l.delta})');
    }
  }
  return buf.toString();
}

/// Geometry / features summary template vs each copy (walls, area, lights, guides).
String formatTypicalFloorGeometryDiff({
  required Room template,
  required List<Room> copies,
}) {
  final tArea = MaterialsCalculator.roomAreaM2(template.walls);
  final tLights = template.lightFixtures.length;
  final tGuides = template.ceilingGuides.length;
  final buf = StringBuffer()
    ..writeln('Геометрия · шаблон «${template.name}»')
    ..writeln(
      'Стены ${template.walls.length} · площадь ${tArea.toStringAsFixed(2)} м² · '
      'свет $tLights · направл. $tGuides',
    );
  if (copies.isEmpty) {
    buf.writeln('Копий нет');
    return buf.toString();
  }
  for (final c in copies) {
    final area = MaterialsCalculator.roomAreaM2(c.walls);
    final dArea = area - tArea;
    final dLights = c.lightFixtures.length - tLights;
    final dGuides = c.ceilingGuides.length - tGuides;
    final dWalls = c.walls.length - template.walls.length;
    final marks = <String>[];
    if (dWalls != 0) marks.add('стены Δ$dWalls');
    if (dArea.abs() > 0.01) marks.add('S Δ${dArea.toStringAsFixed(2)}');
    if (dLights != 0) marks.add('свет Δ$dLights');
    if (dGuides != 0) marks.add('направл. Δ$dGuides');
    buf.writeln(
      marks.isEmpty
          ? '• ${c.name}: совпадает'
          : '• ${c.name}: ${marks.join(' · ')}',
    );
  }
  return buf.toString();
}

/// Rooms whose names start with [prefix] (or template name + space), excluding the template.
List<Room> findTypicalFloorCopies(
  Project project,
  Room template, {
  String? prefix,
}) {
  final pfx = (prefix ?? '${template.name} ').trimRight();
  final out = <Room>[];
  for (final r in project.rooms) {
    if (r.id == template.id) continue;
    if (r.name.startsWith(pfx) && r.name != template.name) {
      out.add(r);
    }
  }
  return out;
}
