import 'ceiling_guides.dart';
import 'models.dart';

const _designGuidesKey = 'design_ceiling_guides';
const _designLightsKey = 'design_light_fixtures';

/// Stable key for comparing guide marks across design/fact snapshots.
String guideBaselineKey(CeilingGuideMark mark) =>
    '${mark.storageKey}:${mark.kind.id}:${mark.anchorAlongIndex}';

String? guideBaselineKeyFromJson(
  Map<String, dynamic> json, {
  double offsetX = 0,
  double offsetY = 0,
  double cellSize = 60,
}) {
  final mark = CeilingGuideMark.fromJson(
    json,
    offsetX: offsetX,
    offsetY: offsetY,
    cellSize: cellSize,
  );
  return mark == null ? null : guideBaselineKey(mark);
}

List<CeilingGuideMark> parseDesignGuideMarks(
  Room room, {
  double offsetX = 0,
  double offsetY = 0,
  double cellSize = 60,
}) {
  final raw = readDesignCeilingGuides(room);
  if (raw == null) return const [];
  final out = <CeilingGuideMark>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final mark = CeilingGuideMark.fromJson(
      Map<String, dynamic>.from(item),
      offsetX: offsetX,
      offsetY: offsetY,
      cellSize: cellSize,
    );
    if (mark != null) out.add(mark);
  }
  return out;
}

Set<String> factGuideKeys(
  Room room, {
  double offsetX = 0,
  double offsetY = 0,
  double cellSize = 60,
}) {
  final out = <String>{};
  for (final json in room.ceilingGuides) {
    final key = guideBaselineKeyFromJson(
      json,
      offsetX: offsetX,
      offsetY: offsetY,
      cellSize: cellSize,
    );
    if (key != null) out.add(key);
  }
  return out;
}

Set<String> designGuideKeysNotInFact(
  Room room, {
  double offsetX = 0,
  double offsetY = 0,
  double cellSize = 60,
}) {
  final design = readDesignCeilingGuides(room);
  if (design == null) return const {};
  final fact = factGuideKeys(room, offsetX: offsetX, offsetY: offsetY, cellSize: cellSize);
  final out = <String>{};
  for (final item in design) {
    if (item is! Map) continue;
    final key = guideBaselineKeyFromJson(
      Map<String, dynamic>.from(item),
      offsetX: offsetX,
      offsetY: offsetY,
      cellSize: cellSize,
    );
    if (key != null && !fact.contains(key)) out.add(key);
  }
  return out;
}

List<CeilingGuideMark> designGuideMarksNotInFact(
  Room room, {
  double offsetX = 0,
  double offsetY = 0,
  double cellSize = 60,
}) {
  final missing = designGuideKeysNotInFact(
    room,
    offsetX: offsetX,
    offsetY: offsetY,
    cellSize: cellSize,
  );
  if (missing.isEmpty) return const [];
  return parseDesignGuideMarks(
    room,
    offsetX: offsetX,
    offsetY: offsetY,
    cellSize: cellSize,
  ).where((m) => missing.contains(guideBaselineKey(m))).toList();
}

List<dynamic>? readDesignCeilingGuides(Room room) {
  final raw = room.layoutViewJson?[_designGuidesKey];
  return raw is List ? List<dynamic>.from(raw) : null;
}

List<List<dynamic>>? readDesignLightFixtures(Room room) {
  final raw = room.layoutViewJson?[_designLightsKey];
  if (raw is! List) return null;
  return raw
      .whereType<List>()
      .map((f) => f.map((e) => e).toList())
      .toList();
}

bool hasDesignCeilingFeaturesBaseline(Room room) =>
    readDesignCeilingGuides(room) != null || readDesignLightFixtures(room) != null;

void ensureDesignCeilingFeaturesBaseline(Room room) {
  final view = Map<String, dynamic>.from(room.layoutViewJson ?? {});
  var changed = false;
  if (!view.containsKey(_designGuidesKey)) {
    view[_designGuidesKey] = List<dynamic>.from(room.ceilingGuides);
    changed = true;
  }
  if (!view.containsKey(_designLightsKey)) {
    view[_designLightsKey] = room.lightFixtures.map((f) => List<dynamic>.from(f)).toList();
    changed = true;
  }
  if (changed) room.layoutViewJson = view;
}

void resetDesignCeilingFeaturesBaseline(Room room) {
  final view = Map<String, dynamic>.from(room.layoutViewJson ?? {});
  final removed =
      view.remove(_designGuidesKey) != null || view.remove(_designLightsKey) != null;
  if (removed) {
    room.layoutViewJson = view.isEmpty ? null : view;
  }
}

Set<String> _lightIdSet(Iterable<List<dynamic>> fixtures) {
  final out = <String>{};
  for (final f in fixtures) {
    if (f.length >= 2) out.add('${f[0]}:${f[1]}');
  }
  return out;
}

(int guideDelta, int lightDelta) ceilingFeaturesDelta(Room room) {
  final designGuides = readDesignCeilingGuides(room);
  final designLights = readDesignLightFixtures(room);
  if (designGuides == null && designLights == null) return (0, 0);

  final factKeys = factGuideKeys(room);
  final designKeys = <String>{};
  for (final item in designGuides ?? const []) {
    if (item is! Map) continue;
    final key = guideBaselineKeyFromJson(Map<String, dynamic>.from(item));
    if (key != null) designKeys.add(key);
  }
  final guideDelta = designGuides != null
      ? (designKeys.difference(factKeys).length +
          factKeys.difference(designKeys).length)
      : 0;
  final factLights = _lightIdSet(room.lightFixtures);
  final designLightIds = designLights != null ? _lightIdSet(designLights) : factLights;
  final lightDelta = (factLights.difference(designLightIds).length +
      designLightIds.difference(factLights).length);
  return (guideDelta, lightDelta);
}

String formatCeilingFeaturesDeltaLabel(Room room) {
  final (g, l) = ceilingFeaturesDelta(room);
  if (g == 0 && l == 0) return 'Направляющие и свет совпадают с проектом';
  final parts = <String>[];
  if (g != 0) parts.add('направл. Δ$g');
  if (l != 0) parts.add('свет Δ$l');
  return parts.join(' · ');
}

Set<String> designLightIdsNotInFact(Room room) {
  final design = readDesignLightFixtures(room);
  if (design == null) return const {};
  final designIds = _lightIdSet(design);
  final factIds = _lightIdSet(room.lightFixtures);
  return designIds.difference(factIds);
}

Set<String> factLightIdsNotInDesign(Room room) {
  final design = readDesignLightFixtures(room);
  if (design == null) return const {};
  final designIds = _lightIdSet(design);
  final factIds = _lightIdSet(room.lightFixtures);
  return factIds.difference(designIds);
}
