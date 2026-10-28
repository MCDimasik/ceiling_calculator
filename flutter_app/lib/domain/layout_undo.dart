import 'ceiling_guides.dart';

/// Undo/redo snapshot for layout screen (grid, lights, guides).
class LayoutEditSnapshot {
  LayoutEditSnapshot({
    required this.gridOffsetX,
    required this.gridOffsetY,
    required this.visualOffsetX,
    required this.visualOffsetY,
    required this.lightIds,
    required this.guidesJson,
  });

  final int gridOffsetX;
  final int gridOffsetY;
  final double visualOffsetX;
  final double visualOffsetY;
  final Set<String> lightIds;
  final Map<String, dynamic> guidesJson;

  factory LayoutEditSnapshot.capture({
    required int gridOffsetX,
    required int gridOffsetY,
    required double visualOffsetX,
    required double visualOffsetY,
    required Set<String> lightIds,
    required Map<String, CeilingGuideMark> guides,
  }) {
    return LayoutEditSnapshot(
      gridOffsetX: gridOffsetX,
      gridOffsetY: gridOffsetY,
      visualOffsetX: visualOffsetX,
      visualOffsetY: visualOffsetY,
      lightIds: Set<String>.from(lightIds),
      guidesJson: guides.map((k, v) => MapEntry(k, v.toJson())),
    );
  }
}

class LayoutUndoStack {
  final List<LayoutEditSnapshot> _undo = [];
  final List<LayoutEditSnapshot> _redo = [];

  bool get canUndo => _undo.length > 1;
  bool get canRedo => _redo.isNotEmpty;

  void seed(LayoutEditSnapshot initial) {
    _undo
      ..clear()
      ..add(initial);
    _redo.clear();
  }

  void push(LayoutEditSnapshot snap) {
    _undo.add(snap);
    _redo.clear();
    if (_undo.length > 40) _undo.removeAt(0);
  }

  LayoutEditSnapshot? undo() {
    if (_undo.length <= 1) return null;
    _redo.add(_undo.removeLast());
    return _undo.last;
  }

  LayoutEditSnapshot? redo() {
    if (_redo.isEmpty) return null;
    final next = _redo.removeLast();
    _undo.add(next);
    return next;
  }
}
