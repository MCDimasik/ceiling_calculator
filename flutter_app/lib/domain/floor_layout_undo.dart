/// Undo/redo for floor grid offset and rotation on finish tab.
class FloorLayoutUndoSnapshot {
  const FloorLayoutUndoSnapshot({
    required this.offsetX,
    required this.offsetY,
    this.rotationDeg = 0,
  });

  final int offsetX;
  final int offsetY;
  final int rotationDeg;
}

class FloorLayoutUndoStack {
  final List<FloorLayoutUndoSnapshot> _undo = [];
  final List<FloorLayoutUndoSnapshot> _redo = [];

  bool get canUndo => _undo.length > 1;
  bool get canRedo => _redo.isNotEmpty;

  void seed(FloorLayoutUndoSnapshot initial) {
    _undo
      ..clear()
      ..add(initial);
    _redo.clear();
  }

  void push(FloorLayoutUndoSnapshot snap) {
    final last = _undo.isEmpty ? null : _undo.last;
    if (last != null &&
        last.offsetX == snap.offsetX &&
        last.offsetY == snap.offsetY &&
        last.rotationDeg == snap.rotationDeg) {
      return;
    }
    _undo.add(snap);
    _redo.clear();
    if (_undo.length > 30) _undo.removeAt(0);
  }

  FloorLayoutUndoSnapshot? undo() {
    if (_undo.length <= 1) return null;
    _redo.add(_undo.removeLast());
    return _undo.last;
  }

  FloorLayoutUndoSnapshot? redo() {
    if (_redo.isEmpty) return null;
    final next = _redo.removeLast();
    _undo.add(next);
    return next;
  }
}

String formatFloorLayoutUndoLabel(FloorLayoutUndoSnapshot snap) {
  final rot = snap.rotationDeg == 0 ? '' : ' · ${snap.rotationDeg}°';
  return '${snap.offsetX}×${snap.offsetY} см$rot';
}
