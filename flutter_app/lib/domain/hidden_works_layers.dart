import 'documentation_model.dart';
import 'finish_model.dart';
import 'floor_covering.dart';
import 'models.dart';
import 'surface_prep_layers.dart';

/// One optional photo slot in the hidden-works sequence (layer → photo).
class HiddenWorkLayerSlot {
  const HiddenWorkLayerSlot({
    required this.id,
    required this.title,
    required this.section,
  });

  /// Stable key for [RoomDocumentationChecklist.stepPhotos].
  final String id;
  final String title;

  /// «Стены» / «Пол» / «Потолок».
  final String section;
}

/// Build photo sequence from room finish layers (optional — does not gate KS-2).
List<HiddenWorkLayerSlot> buildHiddenWorkLayerSlots(Room room) {
  final out = <HiddenWorkLayerSlot>[];

  if (room.finishIncludeWalls) {
    final layers = room.wallFinishLayers.map(FinishLayer.fromJson).where((l) => l.enabled);
    for (final layer in layers) {
      out.add(
        HiddenWorkLayerSlot(
          id: 'hw_wall_${layer.kind.id}',
          title: layer.displayLabel,
          section: 'Стены',
        ),
      );
    }
    if (out.where((s) => s.section == 'Стены').isEmpty) {
      out.add(
        const HiddenWorkLayerSlot(
          id: 'hw_walls',
          title: 'Подготовка / отделка стен',
          section: 'Стены',
        ),
      );
    }
  }

  if (room.finishIncludeFloor) {
    for (final raw in room.floorPrepLayers) {
      final layer = SurfacePrepLayer.fromJson(raw);
      if (!layer.enabled) continue;
      out.add(
        HiddenWorkLayerSlot(
          id: 'hw_floor_${layer.kindId}',
          title: layer.displayName(floor: true),
          section: 'Пол',
        ),
      );
    }
    final covering = FloorCoveringKindX.parse(room.floorCoveringKind);
    out.add(
      HiddenWorkLayerSlot(
        id: 'hw_floor_covering_${covering.id}',
        title: covering.labelRu,
        section: 'Пол',
      ),
    );
  }

  if (room.finishIncludeCeiling) {
    for (final raw in room.ceilingPrepLayers) {
      final layer = SurfacePrepLayer.fromJson(raw);
      if (!layer.enabled) continue;
      out.add(
        HiddenWorkLayerSlot(
          id: 'hw_ceiling_${layer.kindId}',
          title: layer.displayName(floor: false),
          section: 'Потолок',
        ),
      );
    }
    if (room.ceilingGuides.isNotEmpty) {
      out.add(
        const HiddenWorkLayerSlot(
          id: 'hw_ceiling_frame',
          title: 'Каркас потолка',
          section: 'Потолок',
        ),
      );
      out.add(
        const HiddenWorkLayerSlot(
          id: 'hw_ceiling_guides',
          title: 'Направляющие',
          section: 'Потолок',
        ),
      );
    }
    if (room.lightFixtures.isNotEmpty) {
      out.add(
        const HiddenWorkLayerSlot(
          id: 'hw_ceiling_lights',
          title: 'Закладные / свет',
          section: 'Потолок',
        ),
      );
    }
    if (room.layoutConfirmed) {
      out.add(
        const HiddenWorkLayerSlot(
          id: 'hw_ceiling_tiles',
          title: 'Плиты / кассеты',
          section: 'Потолок',
        ),
      );
    }
  }

  return out;
}

int hiddenLayerPhotoCount(RoomDocumentationChecklist cl, String slotId) =>
    cl.photosFor(slotId).length;

(int done, int total) hiddenLayersProgress(
  Room room,
  RoomDocumentationChecklist checklist,
) {
  final slots = buildHiddenWorkLayerSlots(room);
  if (slots.isEmpty) return (0, 0);
  var done = 0;
  for (final s in slots) {
    if (checklist.photosFor(s.id).isNotEmpty ||
        checklist.hiddenWorksConfirmed[s.id] == true) {
      done++;
    }
  }
  return (done, slots.length);
}
