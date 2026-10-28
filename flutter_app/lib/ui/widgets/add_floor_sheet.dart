import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/project_floors.dart';
import 'numeric_input.dart';

/// Result of the add-floor sheet.
class AddFloorResult {
  const AddFloorResult({
    required this.count,
    required this.typical,
    required this.sourceRoomIds,
    this.startNumber,
  });

  final int count;
  final bool typical;
  final List<int> sourceRoomIds;
  final int? startNumber;
}

class _UniqueRoomOption {
  _UniqueRoomOption({
    required this.room,
    required this.floorLabel,
  });

  final Room room;
  final String? floorLabel;
}

/// Deduplicate rooms (typical copies / same name) — keep earliest floor instance.
List<_UniqueRoomOption> _uniqueRoomsForFloorCopy({
  required List<Room> rooms,
  required List<ProjectFloor> floors,
}) {
  final byKey = <String, _UniqueRoomOption>{};
  final floorById = {for (final f in floors) f.id: f};

  int floorOrd(Room r) {
    final id = r.floorId;
    if (id == null) return 0;
    final f = floorById[id];
    if (f == null) return 999;
    return f.floorNumber * 10 + f.typicalIndex;
  }

  final sorted = List<Room>.from(rooms)
    ..sort((a, b) => floorOrd(a).compareTo(floorOrd(b)));

  for (final room in sorted) {
    if (room.id == null) continue;
    // Prefer name+shape fingerprint so renamed copies still collapse.
    final key = '${room.name.trim().toLowerCase()}|${room.walls.length}|'
        '${room.walls.isEmpty ? 0 : room.walls.first.join(",")}';
    if (byKey.containsKey(key)) continue;
    byKey[key] = _UniqueRoomOption(
      room: room,
      floorLabel: roomFloorLabel(room: room, floors: floors) ??
          (projectHasExplicitFloors(floors) ? '1 этаж' : null),
    );
  }
  return byKey.values.toList();
}

/// Bottom sheet: pick rooms to copy, optional typical count.
Future<AddFloorResult?> showAddFloorSheet({
  required BuildContext context,
  required List<Room> rooms,
  required bool typical,
  int suggestedStart = 2,
  List<ProjectFloor> floors = const [],
}) {
  return showModalBottomSheet<AddFloorResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AddFloorSheet(
      rooms: rooms,
      floors: floors,
      typical: typical,
      suggestedStart: suggestedStart,
    ),
  );
}

class _AddFloorSheet extends StatefulWidget {
  const _AddFloorSheet({
    required this.rooms,
    required this.floors,
    required this.typical,
    required this.suggestedStart,
  });

  final List<Room> rooms;
  final List<ProjectFloor> floors;
  final bool typical;
  final int suggestedStart;

  @override
  State<_AddFloorSheet> createState() => _AddFloorSheetState();
}

class _AddFloorSheetState extends State<_AddFloorSheet> {
  late final TextEditingController _countCtrl;
  late final TextEditingController _startCtrl;
  late final List<_UniqueRoomOption> _options;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _countCtrl = TextEditingController(text: widget.typical ? '5' : '1');
    _startCtrl = TextEditingController(text: '${widget.suggestedStart}');
    _options = _uniqueRoomsForFloorCopy(
      rooms: widget.rooms,
      floors: widget.floors,
    );
    for (final o in _options) {
      final id = o.room.id;
      if (id != null) _selected.add(id);
    }
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    _startCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.typical ? 'Типовой этаж' : 'Новый этаж',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            widget.typical
                ? 'Создаётся блок этажей с одинаковыми помещениями'
                : 'Добавить один этаж и при желании скопировать комнаты',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startCtrl,
                  keyboardType: NumericInput.decimalKeyboard,
                  decoration: InputDecoration(
                    labelText: widget.typical
                        ? 'Номер первого этажа'
                        : 'Номер этажа',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              if (widget.typical) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _countCtrl,
                    keyboardType: NumericInput.decimalKeyboard,
                    decoration: const InputDecoration(
                      labelText: 'Сколько этажей',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Скопировать помещения',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.35,
            ),
            child: _options.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Пока нет помещений для копирования'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _options.length,
                    itemBuilder: (context, i) {
                      final opt = _options[i];
                      final id = opt.room.id!;
                      final checked = _selected.contains(id);
                      final subtitle = opt.floorLabel;
                      return CheckboxListTile(
                        dense: true,
                        value: checked,
                        title: Text(opt.room.name),
                        subtitle: subtitle == null ? null : Text(subtitle),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final start = int.tryParse(_startCtrl.text.trim()) ??
                  widget.suggestedStart;
              final count = widget.typical
                  ? (int.tryParse(_countCtrl.text.trim()) ?? 1).clamp(2, 50)
                  : 1;
              Navigator.pop(
                context,
                AddFloorResult(
                  count: count,
                  typical: widget.typical && count > 1,
                  sourceRoomIds: _selected.toList(),
                  startNumber: start,
                ),
              );
            },
            child: Text(
              widget.typical ? 'Создать типовые этажи' : 'Добавить этаж',
            ),
          ),
        ],
      ),
    );
  }
}
