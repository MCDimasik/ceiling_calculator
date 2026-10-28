import 'dart:io';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../domain/documentation_model.dart';
import '../domain/documentation_photos.dart';
import '../domain/hidden_works_layers.dart';
import '../domain/models.dart';
import 'widgets/screen_scaffold.dart';

/// Optional hidden-works sequence: each finish layer → attach photo.
class DocumentationHiddenLayersScreen extends StatefulWidget {
  const DocumentationHiddenLayersScreen({
    super.key,
    required this.projectId,
    required this.roomId,
  });

  final int projectId;
  final int roomId;

  @override
  State<DocumentationHiddenLayersScreen> createState() =>
      _DocumentationHiddenLayersScreenState();
}

class _DocumentationHiddenLayersScreenState
    extends State<DocumentationHiddenLayersScreen> {
  Project? _project;
  Room? _room;
  RoomDocumentationChecklist _checklist = RoomDocumentationChecklist();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final project =
        await AppScope.of(context).projects.getProject(widget.projectId);
    Room? room;
    if (project != null) {
      for (final r in project.rooms) {
        if (r.id == widget.roomId) room = r;
      }
    }
    if (!mounted) return;
    setState(() {
      _project = project;
      _room = room;
      _checklist =
          RoomDocumentationChecklist.fromJson(room?.documentationChecklistJson);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final room = _room;
    if (room?.id == null) return;
    final json =
        roomChecklistJsonForSave(_checklist, room!.documentationChecklistJson);
    await AppScope.of(context).projects.updateRoomChecklist(
          room.id!,
          checklistJson: json,
        );
    room.documentationChecklistJson = json;
  }

  Future<void> _addPhoto(String slotId) async {
    final room = _room;
    if (room?.id == null) return;
    final path = await pickAndStoreDocumentationPhoto(
      projectId: widget.projectId,
      roomId: room!.id!,
      stepId: slotId,
    );
    if (path == null || !mounted) return;
    setState(() {
      final list = List<String>.from(_checklist.stepPhotos[slotId] ?? [])
        ..add(path);
      _checklist.stepPhotos[slotId] = list;
    });
    await _save();
  }

  Future<void> _removePhoto(String slotId, String path) async {
    await removeDocumentationPhoto(path);
    if (!mounted) return;
    setState(() {
      final list = List<String>.from(_checklist.stepPhotos[slotId] ?? [])
        ..remove(path);
      _checklist.stepPhotos[slotId] = list;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));
    }
    final room = _room;
    if (room == null || _project == null) {
      return ScreenScaffold(
        appBar: AppBar(title: const Text('Скрытые работы')),
        body: const Center(child: Text('Комната не найдена')),
      );
    }

    final slots = buildHiddenWorkLayerSlots(room);
    final (done, total) = hiddenLayersProgress(room, _checklist);

    return ScreenScaffold(
      appBar: AppBar(
        title: Text('Скрытые · ${room.name}'),
      ),
      body: slots.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Нет слоёв отделки для фото. '
                  'Задайте пол / стены / потолок в расчёте отделки — '
                  'сюда подтянутся автоматически.\n\n'
                  'Раздел необязательный: КС можно закрывать без фото.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  'Опционально · $done / $total слоёв с фото',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Слой → фото. Не блокирует закрытие КС.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                ..._buildSlotTiles(slots),
              ],
            ),
    );
  }

  List<Widget> _buildSlotTiles(List<HiddenWorkLayerSlot> slots) {
    final widgets = <Widget>[];
    String? lastSection;
    for (final slot in slots) {
      if (slot.section != lastSection) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: lastSection == null ? 0 : 12, bottom: 4),
            child: Text(
              slot.section,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        );
        lastSection = slot.section;
      }
      widgets.add(
        _LayerPhotoCard(
          slot: slot,
          photos: _checklist.photosFor(slot.id),
          onAdd: () => _addPhoto(slot.id),
          onRemove: (path) => _removePhoto(slot.id, path),
        ),
      );
    }
    return widgets;
  }
}

class _LayerPhotoCard extends StatelessWidget {
  const _LayerPhotoCard({
    required this.slot,
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  final HiddenWorkLayerSlot slot;
  final List<String> photos;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    slot.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (photos.isNotEmpty)
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (photos.isNotEmpty)
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final path = photos[i];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(path),
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 72,
                              height: 72,
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton(
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: () => onRemove(path),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(photos.isEmpty ? 'Прикрепить фото' : 'Ещё фото'),
            ),
          ],
        ),
      ),
    );
  }
}
